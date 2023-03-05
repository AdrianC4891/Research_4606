function [data, txOut, rxIn, rxParams] = HelperDVBS2RxInputGenerate(cfg, simParams)
%HelperDVBS2RxInputGenerate Generates DVB-S2 single stream receiver input
%and initializes the receiver parameters
%
%   Note: This is a helper function and its API and/or functionality may
%   change in subsequent releases.
%
%   [DATA, TXOUT, RXIN, RXPARAMS] = HelperDVBS2RxInputGenerate(CFG, ...
%   SIMPARAMS) generates bit stream input, DATA, and waveform samples,
%   TXOUT, receiver input samples corrupted with RF impairments, RXIN, and
%   a structure, RXPARAMS which contains the DVBS2 receiver parameters
%   for the given configuration, CFG and simulation parameters, SIMPARAMS.
%
%   simParams structure fields:
%   sps                           -  Samples per symbol
%   numFrames                     -  Number of PL frames to generate                                   
%   chanBW                        -  Channel bandwidth in Hertz                                                           
%   cfo                           -  Carrier frequency offset in Hertz
%   sco                           -  Sampling clock offset in ppm
%   phNoiseLevel                  -  A vector of phase noise level in
%   dBc/Hz
%
%   rxParams structure fields:
%
%   inputFrameSize                -  Input data size to fill one baseband
%                                    frame
%   xFecFrameSize                 -  PL data frame size
%   UPL                           -  User packet length
%   plFrameSize                   -  PL frame size
%   frameCount                    -  Counter to update PL frame number
%   numPilots                     -  Number of pilot blocks
%   pilotInd                      -  Pilot indices position in PL frame
%   refPilots                     -  PL scrambled reference pilots used in 
%                                    transmission
%   cfBuffer                      -  Buffer to store coarse frequency
%                                    compensated output
%   ffBuffer                      -  Buffer to store fine frequency
%                                    compensated output
%   pilotPhEst                    -  A vector storing the phase estimates
%                                    made on pilots blocks in a frame
%   prevPhaseEst                  -  State variable for carrier phase
%                                    estimation
%   fineFreqCorrVal               -  State variable to store auto
%                                    correlation value used in fine
%                                    frequency error estimation 
%   syncIndex                     -  Frame start index
%   modOrder                      -  Modulation order
%   codeRate                      -  LDPC code rate
%   cwLen                         -  LDPC codeword length

%   Copyright 2020 The MathWorks, Inc.

numFrames = simParams.numFrames;
sps = simParams.sps;

% Initialize the DVB-S2 waveform generator system object.
% Only pilot-aided mode is supported. 
s2WaveGen = dvbs2WaveformGenerator('HasPilots', true);
set(s2WaveGen, cfg);

% Retrieving all the properties of the object in a structure 
s2GenParams = get(s2WaveGen);

% Input data generation
if strcmpi(s2WaveGen.StreamFormat, "TS")
    syncBits = [0 1 0 0 0 1 1 1]'; % Sync byte for TS packet is 47 Hex
    pktLen = 1496;                 % UP length without sync bits is 1496
else
    if s2WaveGen.UPL > 0
        syncBits = randi([0 1], 8, 1);
        pktLen = s2WaveGen.UPL - 8;      % UP length without sync byte
    end
end

% For GS continuous streams
if strcmpi(s2WaveGen.StreamFormat, "GS") && s2WaveGen.UPL == 0
    numBits = s2WaveGen.DFL*numFrames;
    data = randi([0 1], numBits, 1);
else % For TS and GS packetized streams
    numPkts = s2WaveGen.MinNumPackets*numFrames;
    txRawPkts = randi([0 1], pktLen, numPkts);
    txPkts = [repmat(syncBits, 1, numPkts); txRawPkts];
    data = txPkts(:);
end

% DVB-S2 waveform generation. Flush the transmit filter to handle filter delay and retrieve the last PL frame completely 
txOut = [s2WaveGen(data);flushFilter(s2WaveGen)];

% Passing through AWGN channel
 rxIn = awgn(txOut, simParams.EsNodB - 10*log10(sps), 'measured');

% Receiver parameters generation 

[modOrder, codeRate, cwLen] = satcom.internal.dvbs.getS2PHYParams(s2GenParams.MODCOD, s2GenParams.FECFrame); 

dataLen = cwLen/log2(modOrder);

% Pilot sequence and indices generation
slotLen = 90;
pilotBlkFreq = 16; % In slots
numPilotBlks = floor(dataLen/(slotLen*pilotBlkFreq));
if floor(dataLen/(slotLen*16)) == dataLen/(slotLen*pilotBlkFreq)
    numPilotBlks = numPilotBlks - 1;
end
pilotLen = numPilotBlks*36; % one pilot block contains 36 pilot symbols
frameSize = dataLen + pilotLen + slotLen;
plScrambIntSeq = satcom.internal.dvbs.plScramblingIntegerSequence(0);
cMap = [1 1j -1 -1j].';
cSeq = cMap(plScrambIntSeq+1);
[~, pilotInd] = satcom.internal.dvbs.pilotBlock(numPilotBlks);

rxParams.plFrameSize = frameSize;
rxParams.xFecFrameSize = dataLen;
if strcmpi(s2GenParams.StreamFormat, 'TS')
    pktLen = 1496 + 8;  % TS packet length is 1504 bits(1496 + sync byte) 
else
    if s2GenParams.UPL > 0
        pktLen = s2GenParams.UPL; % User packet length including sync byte
    else
        pktLen = 0;
    end
end
if strcmpi(s2GenParams.StreamFormat, 'GS') && s2GenParams.UPL == 0
    rxParams.inputFrameSize  = s2GenParams.DFL;
else
    rxParams.inputFrameSize = s2GenParams.MinNumPackets*pktLen;
end
rxParams.modOrder = modOrder;
rxParams.UPL = pktLen; 
rxParams.codeRate = codeRate;
rxParams.cwLen = cwLen;
rxParams.sps = s2GenParams.SamplesPerSymbol;
rxParams.frameCount = 1;
rxParams.numPilots = numPilotBlks;
rxParams.pilotInd = pilotInd + slotLen;
rxParams.refPilots = (1+1j)/sqrt(2).*cSeq(pilotInd);
rxParams.cfBuffer = [];
rxParams.ffBuffer = complex(zeros(frameSize, 1));
rxParams.pilotPhEst = zeros(numPilotBlks+1, 1);
[rxParams.prevPhaseEst, rxParams.fineFreqCorrVal] = deal(0);
rxParams.syncIndex = 1;
end
