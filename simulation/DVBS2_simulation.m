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
cfgDVBS2.ScalingMethod = "Unit average power"; % Only use in APSK
cfgDVBS2.RolloffFactor = 0.35;
cfgDVBS2.HasPilots = true;
cfgDVBS2.SamplesPerSymbol = 2;

simParams.sps = cfgDVBS2.SamplesPerSymbol;             % Samples per symbol
simParams.numFrames = 50;                              % Number of frames to be processed
simParams.chanBW = 36e6;                               % Channel bandwidth in Hertz
simParams.EbNodB = 2.1;                                % Channel Eb/No in dB

% From Eb/No to Es/No
EbNo = 2.1;
% SamplesPerSymbol ignored if esno mode enabled
EsNo = convertSNR(EbNo,"ebno","esno", "BitsPerSymbol",2, "CodingRate",2/3);
fprintf("EbNo = %f, EsNo = %f\n",EbNo, EsNo);
simParams.EsNodB = 2.1; %EsNo;

%%
[data,txOut,rxIn,rxParams] = DVBS2RxInputGeneratePBNJ(cfgDVBS2,simParams);

% for the sake of testing
% RxIn = txOut;

%% Plot Time Domain Output of TxOut
% BW = 36e6;                                           % Typical satellite channel bandwidth
% Fsym = BW/(1+s2WaveGen.RolloffFactor);
% plot(abs(txOut));


%% Plot txOut constellation
% Transmited signal constellation plot
% rxConst = comm.ConstellationDiagram('Title','Received data', ...
%     'XLimits',[-1 1],'YLimits',[-1 1], ...
%     'ShowReferenceConstellation',false, ...
%     'SamplesPerSymbol',simParams.sps);
% 
% rxConst(txOut(1:length(txOut)))
% 
% %% Plot rxIn constellation
% % Received signal constellation plot
% rxConst = comm.ConstellationDiagram('Title','Received data', ...
%     'XLimits',[-1 1],'YLimits',[-1 1], ...
%     'ShowReferenceConstellation',false, ...
%     'SamplesPerSymbol',simParams.sps);
% rxConst(rxIn(1:length(txOut)))
% 
% %% Transmitted and received signal spectrum visualization
% Rsymb = simParams.chanBW/(1 + cfgDVBS2.RolloffFactor);    
% Fsamp = Rsymb*simParams.sps;
% specAn = dsp.SpectrumAnalyzer('SampleRate',Fsamp, ...
%     'ChannelNames',{'Transmitted waveform','Received waveform'}, ...
%     'ShowLegend',true);
% specAn([txOut, rxIn(1:length(txOut))]);



%% Match Filter of DVBS2 Waveform

RecFilter =  comm.RaisedCosineReceiveFilter( ...
                'RolloffFactor', cfgDVBS2.RolloffFactor, ...
                'InputSamplesPerSymbol', cfgDVBS2.SamplesPerSymbol, ...
                'DecimationFactor', cfgDVBS2.SamplesPerSymbol, ...
                'FilterSpanInSymbols', 10);

% Match filter on tranmsitted data
% incorporate 
postRx = RecFilter(rxIn);
postRx = postRx(RecFilter.FilterSpanInSymbols+1:end);


%% Recover Bits


normFlag = cfgDVBS2.MODCOD >= 18 && strcmpi(cfgDVBS2.ScalingMethod,'Outer radius as 1');

% Initialize error computing parameters
[numFramesLost,pktsErr,bitsErr,pktsRec] = deal(0);

% Initialize data indexing variables
stIdx = 0;
dataSize = rxParams.inputFrameSize;
plFrameSize = rxParams.plFrameSize;
dataStInd = 1;
isLastFrame = false;
% symSyncOutLen = zeros(rxParams.initialTimeFreqSync,1);

% while stIdx < length(rxIn)

    % Use one DVB-S2 PL frame for each iteration.
%     endIdx = stIdx + rxParams.plFrameSize*simParams.sps;
% 
%     % In the last iteration, all the remaining samples in the received
%     % waveform are considered.
%     isLastFrame = endIdx > length(rxIn);
%     endIdx(isLastFrame) = length(rxIn);
%     rxData = rxIn(stIdx+1:endIdx);

    % Decode the PL header by using the HelperDVBS2PLHeaderRecover helper
    % function. Start of frame (SOF) is 26 symbols, which are discarded
    % before header decoding. They are only required for frame
    % synchronization.
    rxPLSCode = postRx(27:90);
    [M,R,fecFrame,pilotStat] = HelperDVBS2PLHeaderRecover(rxPLSCode);
    xFECFrameLen = fecFrame/log2(M);
    % Validate the decoded PL header.
    if  M ~= rxParams.modOrder || R ~= rxParams.codeRate || ...
            fecFrame ~= rxParams.cwLen || ~pilotStat
        fprintf('%s\n','PL header decoding failed')
        dataStInd = dataStInd + 1;
    else % Demodulation and decoding
        for frameCnt = 1:length(postRx)/plFrameSize
            rxFrame = postRx((frameCnt-1)*plFrameSize+1:frameCnt*plFrameSize);
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
% end

%% Compute the BER and PER

% For GS and TS packetized streams
if pktsRec == 0
    fprintf("All frames are lost. No packets are retrieved from BB frames.")
else
    if strcmpi(cfgDVBS2.StreamFormat,'TS')
        pktLen = 1504;
    else
        pktLen = cfgDVBS2.UPL;      % UP length including sync byte
    end
    ber = bitsErr/(pktsRec*pktLen);
    per = pktsErr/pktsRec;
    fprintf('PER: %1.2e\n',per)
    fprintf('BER: %1.2e\n',ber)
end


%%
% tx_sps = 2;
% tx_fspan = 10;
% 
% rx_sps = 2;
% rx_fspan = 10;
% 
% txfilter = comm.RaisedCosineTransmitFilter('OutputSamplesPerSymbol',tx_sps, 'FilterSpanInSymbols',tx_fspan);
% 
% rxfilter = comm.RaisedCosineReceiveFilter('InputSamplesPerSymbol',rx_sps, ...
%     'DecimationFactor',rx_sps,'FilterSpanInSymbols',rx_fspan);
% 
% 
% preTx = 2*randi([0 1],100,1) - 1;
% preTx = [preTx; zeros(tx_fspan,1)]; % add padding
% y = txfilter(preTx);
% 
% postRx = rxfilter(y);
% 
% delay = txfilter.FilterSpanInSymbols;
% x = (1:(length(preTx) - delay));
% plot(x,preTx(1:end-delay),x,postRx(delay+1:end))
% legend('Pre-Tx filter','Post-Rx filter')
