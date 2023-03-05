function [out, isFrameLost, crcOut, streamIdx] = HelperDVBS2StreamRecover(rxBBFrame,varargin)
%HelperDVBS2StreamRecover Recovers user packets or bit stream from
%DVB-S2/S2X baseband frames
%
%   Note: This is a helper function and its API and/or functionality may
%   change in subsequent releases.
%
%   [OUT,ISFRAMELOST,CRCOUT,STREAMIDX] = HelperDVBS2StreamRecover( ...
%   RXBBFRAME) recovers user packets or continuous bit stream, OUT from
%   baseband frame, rxBBFrame. The recovery consists of baseband
%   descrambling, baseband header CRC check, user packet or bit stream
%   reconstruction from data field, and packet CRC check. RXBBFRAME must be
%   a binary column vector.
% 
%   OUT is a binary column vector of real values. ISFRAMELOST is a logical
%   scalar indicating the baseband header CRC check status. CRCOUT is a
%   logical vector indicating the CRC check status of user packets. If
%   output is in continuous bit stream mode, CRCOUT is defined as an empty
%   column vector. STREAMIDX is a positive integer in the range [1, 256].

%   Copyright 2020-2021 The MathWorks, Inc.

if ~isempty(varargin)
    isWideband = varargin{1};
else
   isWideband = false; 
end
persistent deScramSeq crcDetect
if isempty(deScramSeq)
    hSeq = comm.PNSequence('Polynomial', [15 1 0],  ...
        'InitialConditions', [1 0 0 1 0 1 0 1 0 0 0 0 0 0 0], ...
        'SamplesPerFrame', 58192, 'Mask', 15);
   deScramSeq = hSeq();
end

if isempty(crcDetect)
    crcDetect = comm.CRCDetector('Polynomial',[1 1 1 0 1 0 1 0 1]);
end

bbLen = length(rxBBFrame);
rxBBFrame = xor(rxBBFrame, deScramSeq(1:bbLen));

% Header CRC detect
[bbHeader, hasCRCFailed] = crcDetect(rxBBFrame(1:80));
isFrameLost = false;
if ~hasCRCFailed
    streamIdx = int32(comm.internal.utilities.convertBit2Int(bbHeader(9:16), 8)+1);
    DFL = double(comm.internal.utilities.convertBit2Int(bbHeader(33:48), 16));
    if isWideband
     cond = streamIdx > 8 || 80+DFL > length(rxBBFrame);
    else
      cond = streamIdx > 1 || 80+DFL > length(rxBBFrame);
    end
    if cond
        isFrameLost = true;
    end
else
    isFrameLost = true;
end
 
if ~isFrameLost 
    if ~bbHeader(1) && bbHeader(2)
        pktStat = false;
    else
        pktStat = true;
    end
    dataField = rxBBFrame(81:80+DFL);
    % For packetized input streams
    if pktStat
        UPL = double(comm.internal.utilities.convertBit2Int(bbHeader(17:32), 16));
        numPkts = floor(DFL/UPL);
        out = zeros(UPL*numPkts, 1, 'int8');
        pktErr = zeros(numPkts, 1, 'logical');
        syncField = bbHeader(49:56);
        for i = 1:numPkts
            [pkt, pktErr(i)] = crcDetect(dataField((i-1)*UPL+1:i*UPL));
            out((i-1)*UPL+1:i*UPL) = int8([syncField;pkt]);
        end
        crcOut = ~logical(pktErr);
    else
        % For continuous bit streams
        crcOut = zeros(0,1,'logical');
        out = int8(dataField);
    end
else
    crcOut = zeros(0,1,'logical');
    streamIdx = int32(0);
    out = int8(rxBBFrame(81:end));
end