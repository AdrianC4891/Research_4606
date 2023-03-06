%% Add LDPC matrices
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
simParams.numFrames = 20;                              % Number of frames to be processed
simParams.chanBW = 36e6;                               % Channel bandwidth in Hertz
simParams.EbNodB = 2.1;                                % Channel Eb/No in dB

%%
[data,txOut,rxIn,rxParams] = DVBS2RxInputGeneratePBNJ(cfgDVBS2,simParams);


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
dataSize = rxParams.inputFrameSize;
plFrameSize = rxParams.plFrameSize;
dataStInd = 1;
isLastFrame = false;

% Decode the PL header by using the HelperDVBS2PLHeaderRecover helper
% function. Start of frame (SOF) is 26 symbols, which are discarded
% before header decoding. They are only required for frame
% synchronization.
rxPLSCode = postRx(27:90);
[M,R,fecFrame,pilotStat] = HelperDVBS2PLHeaderRecover(rxPLSCode);
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
        if ~isFrameLost
            bitsErr = bitsErr + sum(data(bitInd) ~= decBits);
        end
        dataStInd = dataStInd + 1;
    end
end

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

