function [fer,pctPLH,pctPLF] = DVBS2_FER_calculator(cfgDVBS2, simParams)

    [data,~,rxIn,rxParams] = DVBS2RxInputGeneratePBNJ(cfgDVBS2,simParams);
    
    % Match Filter of DVBS2 Waveform
    
    RecFilter =  comm.RaisedCosineReceiveFilter( ...
                    'RolloffFactor', cfgDVBS2.RolloffFactor, ...
                    'InputSamplesPerSymbol', cfgDVBS2.SamplesPerSymbol, ...
                    'DecimationFactor', cfgDVBS2.SamplesPerSymbol, ...
                    'FilterSpanInSymbols', 10);
    
    % Match filter on tranmsitted data
    % incorporate 
    postRx = RecFilter(rxIn);
    postRx = postRx(RecFilter.FilterSpanInSymbols+1:end);
    
    
    % Recover Bits
    
    normFlag = cfgDVBS2.MODCOD >= 18 && strcmpi(cfgDVBS2.ScalingMethod,'Outer radius as 1');
    
    % Initialize error computing parameters
    [numFramesLost,pktsErr,bitsErr,pktsRec] = deal(0);
    
    % Initialize data indexing variables
    dataSize = rxParams.inputFrameSize;
    plFrameSize = rxParams.plFrameSize;
    dataStInd = 1;
    

    % Demodulation and decoding
    for frameCnt = 1:length(postRx)/plFrameSize
        rxFrame = postRx((frameCnt-1)*plFrameSize+1:frameCnt*plFrameSize);

        % Decode the PL header by using the HelperDVBS2PLHeaderRecover helper
        % function. Start of frame (SOF) is 26 symbols, which are discarded
        % before header decoding. They are only required for frame
        % synchronization.
        rxPLSCode = rxFrame(27:90);
        [M,R,fecFrame,pilotStat] = HelperDVBS2PLHeaderRecover(rxPLSCode);
        % Validate the decoded PL header.
        if  M ~= rxParams.modOrder || R ~= rxParams.codeRate || ...
                fecFrame ~= rxParams.cwLen || ~pilotStat
            fprintf('%s\n','PL header decoding failed')
            dataStInd = dataStInd + 1;
            numFramesLost = numFramesLost + 1;
            continue
        end


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
    
    fer = numFramesLost/simParams.numFrames; % frame error rate calculation
    pctPLH = rxParams.pctPLH;
    pctPLF = rxParams.pctPLF;
    % Compute the BER and PER
    
    % For GS and TS packetized streams
    if pktsRec == 0
        fprintf("All frames are lost. No packets are retrieved from BB frames.")
        ber = 0; % If all frames lost, BER is set to 0
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


end