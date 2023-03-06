function [M, codeRate, fecFrame, pilotStat] = HelperDVBS2PLHeaderRecover(rxPLSCode)
%HelperDVBS2PLHeaderRecover Recovers PL signaling information from DVB-S2
%header field
%
%   Note: This is a helper function and its API and/or functionality may
%   change in subsequent releases.
% 
%   [M, CODERATE, FECFRAME, PILOTSTAT] = ...
%   HelperDVBS2PLHeaderRecover(RXPLSCODE) recovers physical layer (PL)
%   signaling information such as modulation order, M, LDPC code rate,
%   CODERATE, FEC frame length, FECFRAME, and the presence/absence of
%   pilots, PILOTSTAT from physical layer signaling code, RXPLSCODE. The
%   function performs pi/2-BPSK soft demodulation, descrambling and ML
%   decoding. RXPLSCODE is a complex 64-by-1 vector.
%
%   Demodulation is performed according to the constellation given in ETSI
%   EN 302 307 Section 5.5.2.
%
%   References:
%   ETSI Standard EN 302 307-1 V1.4.1(2014-11): Digital Video Broadcasting
%   (DVB); Second generation framing structure, channel coding and
%   modulation systems for Broadcasting, Interactive Services, News
%   Gathering and other broadband satellite applications (DVB-S2)

%   Copyright 2020-2022 The MathWorks, Inc.

% pi/2 - BPSK soft demodulation (+ve -> 0, -ve -> 1)
softBits = zeros(64, 1); % Header PLS code length is 64
softBits(1:2:end) = real(rxPLSCode(1:2:end))+imag(rxPLSCode(1:2:end));
softBits(2:2:end) = imag(rxPLSCode(2:2:end))-real(rxPLSCode(2:2:end));

% de-scrambling
scramSeq = logical([0 1 1 1 0 0 0 1 1 0 0 1 1 1 0 1 1 0 0 0 0 0 1 1 1 1 0 0 1 0 0 1 0 1 0 1 0 0 1 1 0 1 0 0 0 0 1 0 0 0 1 0 1 1 0 1 1 1 1 1 1 0 1 0]');
softBits(scramSeq) = -softBits(scramSeq);

% Maximum-likelihood decoding
m = 64;
allMsgs = int2bit(0:m-1, 6, 0)'; % one per row
genMat = [0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1 0 1; ...
          0 0 1 1 0 0 1 1 0 0 1 1 0 0 1 1 0 0 1 1 0 0 1 1 0 0 1 1 0 0 1 1; ...
          0 0 0 0 1 1 1 1 0 0 0 0 1 1 1 1 0 0 0 0 1 1 1 1 0 0 0 0 1 1 1 1; ...
          0 0 0 0 0 0 0 0 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 1 1 1 1 1 1 1 1; ...
          0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1; ...
          1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1 1];
% Codeword length is 32
softEncMsgs = zeros(32, m);
for i = 1:m
    encMsg = mod(allMsgs(i,:)*genMat,2);
    softEncMsgs(:,i) = 1-2*encMsg;
end
possMsg = zeros(64, 128);
possMsg(1:2:end,:) = repmat(softEncMsgs,1,2);
possMsg(2:2:end,1:64) = softEncMsgs;
possMsg(2:2:end,65:end) = -softEncMsgs;
%   Euclidean distance metric
distMet = sum(abs(repmat(softBits,1,2*m) - possMsg).^2,1)./sum(abs(possMsg).^2,1);
%   Select the msg bits corresponding to the minimum
index = find(distMet==min(distMet),1);
if index > 64
    pilotStat = 1;
    index = index-64;
else
    pilotStat = 0;
end
decBits = allMsgs(index,:);
modCod = comm.internal.utilities.convertBit2Int(decBits(1:5)',5);
if decBits(6)
    fecType = 'short';
else
    fecType = 'normal';
end
                      
inValidListN = [0 29 30 31]; % Reserved list
invalidListS = [0 29 30 31 11 17 23 28]; % Reserved list and MODCOD corresponding to 9/10 code rate
% short frame invalid codes
if (decBits(6) && any(invalidListS == modCod)) || ...
        (~decBits(6) && any(inValidListN == modCod)) % normal frame invalid codes
    [M, codeRate, fecFrame] = deal(0);
else
    [M, codeRate, fecFrame] = satcom.internal.dvbs.getS2PHYParams(modCod, fecType);
end
end
