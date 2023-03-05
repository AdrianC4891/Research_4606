%%
% Add LDPC matrices
if ~exist('dvbs2xLDPCParityMatrices.mat','file')
    if ~exist('s2xLDPCParityMatrices.zip','file')
        url = 'https://ssd.mathworks.com/supportfiles/spc/satcom/DVB/s2xLDPCParityMatrices.zip';
        websave('s2xLDPCParityMatrices.zip',url);
        unzip('s2xLDPCParityMatrices.zip');
    end
addpath('s2xLDPCParityMatrices');
end

%%
cfgDVBS2.StreamFormat = "TS";
cfgDVBS2.FECFrame = "normal";
cfgDVBS2.MODCOD = 6;                             % QPSK 2/3
cfgDVBS2.DFL = 42960;
cfgDVBS2.ScalingMethod = "Unit average power";
cfgDVBS2.RolloffFactor = 0.35;
cfgDVBS2.HasPilots = true;
cfgDVBS2.SamplesPerSymbol = 2;

%%
simParams.sps = cfgDVBS2.SamplesPerSymbol;             % Samples per symbol
simParams.numFrames = 1;                              % Number of frames to be processed
simParams.chanBW = 36e6;                               % Channel bandwidth in Hertz
simParams.cfo = 0;                                   % Carrier frequency offset in Hertz
simParams.sco = 0;                                     % Sampling clock offset in parts
                                                       % per million
% simParams.phNoiseLevel = "Low";         % Phase noise level provided as
                                                       % 'Low', 'Medium', or 'High'
simParams.EsNodB = 15;

%%

[data,txOut,rxIn,rxParams] = HelperDVBS2RxInputGenerate(cfgDVBS2,simParams);


%% Plot txOut constellation
% Transmited signal constellation plot
rxConst = comm.ConstellationDiagram('Title','Received data', ...
    'XLimits',[-1 1],'YLimits',[-1 1], ...
    'ShowReferenceConstellation',false, ...
    'SamplesPerSymbol',simParams.sps);

rxConst(txOut(1:length(txOut)))

%% Plot rxIn constellation
% Received signal constellation plot
rxConst = comm.ConstellationDiagram('Title','Received data', ...
    'XLimits',[-1 1],'YLimits',[-1 1], ...
    'ShowReferenceConstellation',false, ...
    'SamplesPerSymbol',simParams.sps);
rxConst(rxIn(1:length(txOut)))

%% Begin Data Recovery

rxParams.carrSyncLoopBW = 1e-2*0.023;        % Coarse frequency estimator loop bandwidth
                                             % normalized by symbol rate
rxParams.symbSyncLoopBW = 8e-3;              % Symbol timing synchronizer loop bandwidth
                                             % normalized by symbol rate
rxParams.symbSyncLock  = 6;                  % Number of frames required for symbol
                                             % timing error convergence
rxParams.frameSyncLock = 1;                  % Number of frames required for frame
                                             % synchronization
rxParams.coarseFreqLock = 3;                 % Number of frames required for coarse
                                             % frequency acquisition
rxParams.fineFreqLock = 6;                   % Number of frames required for fine
                                             % frequency estimation
rxParams.hasFinePhaseCompensation = false;   % Flag to indicate whether fine phase
                                             % compensation is used
rxParams.finePhaseSyncLoopBW = 3.5e-4;       % Fine phase compensation loop bandwidth
                                             % normalized by symbol rate

% Total frames taken for symbol timing and coarse frequency lock to happen
rxParams.initialTimeFreqSync = rxParams.symbSyncLock + rxParams.frameSyncLock + ...
    rxParams.coarseFreqLock;
% Total frames used for overall synchronization 
rxParams.totalSyncFrames = rxParams.initialTimeFreqSync + rxParams.fineFreqLock;

% Create time frequency synchronization System object by using
% HelperDVBS2TimeFreqSynchronizer helper object
timeFreqSync = HelperDVBS2TimeFreqSynchronizer( ...
    'CarrSyncLoopBW',rxParams.carrSyncLoopBW, ...
    'SymbSyncLoopBW',rxParams.symbSyncLoopBW, ...
    'SamplesPerSymbol',simParams.sps, ...
    'DataFrameSize',rxParams.xFecFrameSize, ...
    'SymbSyncTransitFrames',rxParams.symbSyncLock, ...
    'FrameSyncAveragingFrames',rxParams.frameSyncLock);

% Create fine phase compensation System object by using
% HelperDVBS2FinePhaseCompensator helper object. Fine phase
% compensation is only required for 16 and 32 APSK modulated frames
% if cfgDVBS2.MODCOD >= 6 && rxParams.hasFinePhaseCompensation
%     finePhaseSync = HelperDVBS2FinePhaseCompensator( ...
%         'DataFrameSize',rxParams.xFecFrameSize, ...
%         'NormalizedLoopBandwidth',rxParams.finePhaseSyncLoopBW);
% end

normFlag = cfgDVBS2.MODCOD >= 6 && strcmpi(cfgDVBS2.ScalingMethod,'Outer radius as 1');

% Initialize error computing parameters
[numFramesLost,pktsErr,bitsErr,pktsRec] = deal(0);

% Initialize data indexing variables
stIdx = 0;
dataSize = rxParams.inputFrameSize;
plFrameSize = rxParams.plFrameSize;
dataStInd = rxParams.totalSyncFrames + 1;
isLastFrame = false;
symSyncOutLen = zeros(rxParams.initialTimeFreqSync,1);


%% Recover data

while stIdx < length(rxIn)

    % Use one DVB-S2 PL frame for each iteration.
    endIdx = stIdx + rxParams.plFrameSize*simParams.sps;

    % In the last iteration, all the remaining samples in the received
    % waveform are considered.
    isLastFrame = endIdx > length(rxIn);
    endIdx(isLastFrame) = length(rxIn);
    rxData = rxIn(stIdx+1:endIdx);

    % After coarse frequency offset loop is converged, the FLL works with a
    % reduced loop bandwidth.
    if rxParams.frameCount < rxParams.initialTimeFreqSync
        coarseFreqLock = false;
    else
        coarseFreqLock = true;
    end

    % Retrieve the last frame samples.
    if isLastFrame
        resSymb = plFrameSize - length(rxParams.cfBuffer);
        resSampCnt = resSymb*rxParams.sps - length(rxData);
        if resSampCnt >= 0    % Inadequate number of samples to fill last frame
            syncIn = [rxData;zeros(resSampCnt, 1)];
        else                  % Excess samples are available to fill last frame
            syncIn = rxData(1:resSymb*rxParams.sps);
        end
    else
        syncIn = rxData;
    end

    % Apply matched filtering, symbol timing synchronization, frame
    % synchronization, and coarse frequency offset compensation.
    [coarseFreqSyncOut,syncIndex,phEst] = timeFreqSync(syncIn,coarseFreqLock);
    if rxParams.frameCount <= rxParams.initialTimeFreqSync
        symSyncOutLen(rxParams.frameCount) = length(coarseFreqSyncOut);
        if any(abs(diff(symSyncOutLen(1:rxParams.frameCount))) > 5)
            error(['Symbol timing synchronization failed. The loop will not ' ...
                'converge. No frame will be recovered. Update the symbSyncLoopBW ' ...
                'parameter according to the EsNo setting for proper loop convergence.']);
        end
    end

    rxParams.syncIndex = syncIndex;

    % The PL frame start index lies somewhere in the middle of the chunk being processed.
    % From fine frequency estimation onwards, the processing happens as a PL frame.
    % A buffer is used to store symbols required to fill one PL frame.
    if isLastFrame
        resCnt = resSymb - length(coarseFreqSyncOut);
        if resCnt <= 0
            fineFreqIn = [rxParams.cfBuffer; coarseFreqSyncOut(1:resSymb)];
        else
            fineFreqIn = [rxParams.cfBuffer; coarseFreqSyncOut; zeros(resCnt, 1)];
        end
    elseif rxParams.frameCount > 1
        fineFreqIn = [rxParams.cfBuffer; coarseFreqSyncOut(1:rxParams.plFrameSize-length(rxParams.cfBuffer))];
    end

    % Estimate the fine frequency error by using the HelperDVBS2FineFreqEst
    % helper function.
    % Add 1 to the conditional check because the buffer used to get one PL
    % frame introduces a delay of one to the loop count.
    if (rxParams.frameCount > rxParams.initialTimeFreqSync + 1) && ...
            (rxParams.frameCount <= rxParams.totalSyncFrames + 1)
        rxParams.fineFreqCorrVal = HelperDVBS2FineFreqEst( ...
            fineFreqIn(rxParams.pilotInd),rxParams.numPilots, ...
            rxParams.refPilots,rxParams.fineFreqCorrVal);
    end
    if rxParams.frameCount >= rxParams.totalSyncFrames + 1
        fineFreqLock = true;
    else
        fineFreqLock = false;
    end

    if fineFreqLock
        % Normalize the frequency estimate by the input symbol rate
        % freqEst = angle(R)/(pi*(N+1)), where N (18) is the number of elements
        % used to compute the mean of auto correlation (R) in
        % HelperDVBS2FineFreqEst.
        freqEst = angle(rxParams.fineFreqCorrVal)/(pi*(19));

        % Generate the symbol indices using frameCount and plFrameSize.
        % Subtract 2 from the rxParams.frameCount because the buffer used to get one
        % PL frame introduces a delay of one to the count.
        ind = (rxParams.frameCount-2)*plFrameSize:(rxParams.frameCount-1)*plFrameSize-1;
        phErr = exp(-1j*2*pi*freqEst*ind);
        fineFreqOut = fineFreqIn.*phErr(:);

        % Estimate the phase error estimation by using the HelperDVBS2PhaseEst
        % helper function.
        [phEstRes,rxParams.prevPhaseEst] = HelperDVBS2PhaseEst( ...
            fineFreqOut(rxParams.pilotInd),rxParams.refPilots,rxParams.prevPhaseEst);

        % Compensate for the residual frequency and phase offset by using
        % the
        % HelperDVBS2PhaseCompensate helper function.
        % Use two frames for initial phase error estimation. Starting with the
        % second frame, use the phase error estimates from the previous frame and
        % the current frame in compensation.
        % Add 3 to the frame count comparison to account for delays: One
        % frame due to rxParams.cfBuffer delay and two frames used for phase
        % error estimate.
        if rxParams.frameCount >= rxParams.totalSyncFrames + 3
            coarsePhaseCompOut = HelperDVBS2PhaseCompensate(rxParams.ffBuffer, ...
                rxParams.pilotEst,rxParams.pilotInd,phEstRes(2));
            % MODCOD >= 6 corresponds to APSK modulation schemes
            if cfgDVBS2.MODCOD >= 6 && rxParams.hasFinePhaseCompensation
                phaseCompOut = finePhaseSync(coarsePhaseCompOut);
            else
                phaseCompOut = coarsePhaseCompOut;
            end
        end

        rxParams.ffBuffer = fineFreqOut;
        rxParams.pilotEst = phEstRes;

        % The phase compensation on the data portion is performed by
        % interpolating the phase estimates computed on consecutive pilot
        % blocks. The second phase estimate is not available for the data
        % portion after the last pilot block in the last frame. Therefore,
        % the slope of phase estimates computed on all pilot blocks in the
        % last frame is extrapolated and used to compensate for the phase
        % error on the final data portion.
        if isLastFrame
            pilotBlkLen = 36;    % Symbols
            pilotBlkFreq = 1476; % Symbols
            avgSlope = mean(diff(phEstRes(2:end)));
            chunkLen = rxParams.plFrameSize - rxParams.pilotInd(end) + ...
                rxParams.pilotInd(pilotBlkLen);
            estEndPh = phEstRes(end) + avgSlope*chunkLen/pilotBlkFreq;
            coarsePhaseCompOut1 = HelperDVBS2PhaseCompensate(rxParams.ffBuffer, ...
                rxParams.pilotEst,rxParams.pilotInd,estEndPh);
            % MODCOD >= 6 corresponds to APSK modulation schemes
            if cfgDVBS2.MODCOD >= 6 && rxParams.hasFinePhaseCompensation
                phaseCompOut1 = finePhaseSync(coarsePhaseCompOut1);
            else
                phaseCompOut1 = coarsePhaseCompOut1;
            end
        end
    end

    % Recover the input bit stream.
    if rxParams.frameCount >= rxParams.totalSyncFrames + 3
        isValid = true;
        if isLastFrame
            syncOut = [phaseCompOut; phaseCompOut1];
        else
            syncOut = phaseCompOut;
        end
    else
        isValid = false;
        syncOut = [];
    end

    % Update the buffers and counters.
    rxParams.cfBuffer = coarseFreqSyncOut(rxParams.syncIndex:end);
    rxParams.syncIndex = syncIndex;
    rxParams.frameCount = rxParams.frameCount + 1;

    if isValid  % Data valid signal

        % Decode the PL header by using the HelperDVBS2PLHeaderRecover helper
        % function. Start of frame (SOF) is 26 symbols, which are discarded
        % before header decoding. They are only required for frame
        % synchronization.
        rxPLSCode = syncOut(27:90);
        [M,R,fecFrame,pilotStat] = HelperDVBS2PLHeaderRecover(rxPLSCode);
        xFECFrameLen = fecFrame/log2(M);
        % Validate the decoded PL header.
        if M ~= rxParams.modOrder || R ~= rxParams.codeRate || ...
                fecFrame ~= rxParams.cwLen || ~pilotStat
            fprintf('%s\n','PL header decoding failed')
            dataStInd = dataStInd + 1;
        else % Demodulation and decoding
            for frameCnt = 1:length(syncOut)/plFrameSize
                rxFrame = syncOut((frameCnt-1)*plFrameSize+1:frameCnt*plFrameSize);
                % Estimate noise variance by using
                % HelperDVBS2NoiseVarEstimate helper function.
                nVar = HelperDVBS2NoiseVarEstimate(rxFrame,rxParams.pilotInd,...
                    rxParams.refPilots,normFlag);
                % The data begins at symbol 91 (after the header symbols).
                rxDataFrame = rxFrame(91:end);
                % Recover the BB frame.
                rxBBFrame = satcom.internal.dvbs.s2BBFrameRecover(rxDataFrame,M,R, ...
                    fecFrame,pilotStat,nVar,false);
                % Recover the input bit stream by using
                % HelperDVBS2StreamRecover helper function.
                if strcmpi(cfgDVBS2.StreamFormat,'GS') && ~rxParams.UPL
                    [decBits,isFrameLost] = HelperDVBS2StreamRecover(rxBBFrame);
                    if ~isFrameLost && length(decBits) ~= dataSize
                        isFrameLost = true;
                    end
                else
                    [decBits,isFrameLost,pktCRC] = HelperDVBS2StreamRecover(rxBBFrame);
                    if ~isFrameLost && length(decBits) ~= dataSize
                        isFrameLost = true;
                        pktCRC = zeros(0,1,'logical');
                    end
                    % Compute the packet error rate for TS or GS packetized
                    % mode.
                    pktsErr = pktsErr + numel(pktCRC) - sum(pktCRC);
                    pktsRec = pktsRec + numel(pktCRC);
                end
                if ~isFrameLost
                    ts = sprintf('%s','BB header decoding passed.');
                else
                    ts = sprintf('%s','BB header decoding failed.');
                end
                % Compute the number of frames lost. CRC failure of baseband header
                % is considered a frame loss.
                numFramesLost = isFrameLost + numFramesLost;
                fprintf('%s(Number of frames lost = %1d)\n',ts,numFramesLost)
                % Compute the bits in error.
                bitInd = (dataStInd-1)*dataSize+1:dataStInd*dataSize;
                if isLastFrame && ~isFrameLost
                    bitsErr = bitsErr + sum(data(bitInd) ~= decBits);
                else
                    if ~isFrameLost
                        bitsErr = bitsErr + sum(data(bitInd) ~= decBits);
                    end
                end
                dataStInd = dataStInd + 1;
            end
        end
    end
    stIdx = endIdx;
end


