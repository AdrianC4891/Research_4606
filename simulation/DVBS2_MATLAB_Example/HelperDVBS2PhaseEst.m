function [phErrEst, prevPhErrEst] = HelperDVBS2PhaseEst(rxPilots, ...
    refPilots, prevPhErrEst, varargin)
%HelperDVBS2PhaseEst Estimate residual carrier frequency and phase error
%using pilot blocks in DVB-S2/S2X frames
%
%   Note: This is a helper function and its API and/or functionality may
%   change in subsequent releases.
%
%   [PHERREST,PREVPHERREST] = HelperDVBS2PhaseEst(RXPILOTS,REFPILOTS, ...
%   PREVPHERREST) estimates the residual frequency error and carrier phase
%   error using the received pilots, RXPILOTS, PL scrambled reference
%   pilots, REFPILOTS. The phase estimated on consecutive pilot slots are
%   used to compensate for the data portion of the slot. The phase
%   estimated on the last pilot block of previous frame, PREVPHERREST is
%   used in unwrapping the phase estimates computed on the current PL
%   frame. The residual carrier frequency error should be in the order of
%   1e-4 of symbol rate for the estimation to be accurate.
%
%   [PHERREST, PREVPHERREST] = HelperDVBS2PhaseEst(RXPILOTS, REFPILOTS, ...
%   PREVPHERREST, ISVLSNR, SETNUM, ALPHA) estimates the residual frequency
%   error and carrier phase error for VL-SNR frames using the
%   additional information from VL-SNR set number, SETNUM and slope used in
%   unwrapping the estimate, ALPHA. VL-SNR set number is used for
%   identifying the different pilot structure between 
%
%   References:
%   E. Casini, R. De Gaudenzi and A. Ginesi: "DVB-S2
%   modem algorithms design and performance over typical satellite
%   channels", International Journal on Satellite Communication
%   Networks, Volume 22, Issue 3.

%   Copyright 2020-2021 The MathWorks, Inc.

if isempty(varargin)
    isVLSNR = false;
    setNum = 0;
    alpha = 1;
else
    isVLSNR = varargin{1};
    setNum = varargin{2};
    alpha =  varargin{3};
end
if isVLSNR
    if setNum == 1 % VL-SNR set 1 pilot structure
        blkLens = zeros(43,1);
        blkLens(1:2:end) = 36;
        blkLens(2:2:36) = 34;
        blkLens(38:2:end) = 36;
    else % VL-SNR set 2 pilot structure
        blkLens = zeros(21,1);
        blkLens(1:2:end) = 36;
        blkLens(2:2:18) = 32;
        blkLens(20) = 36;
    end
    numBlks = numel(blkLens);
    prevPhErrEst = 0;
else  % Regular PL frames
    blkLen = 36; % Number of pilots in a pilot block
    numBlks = length(rxPilots)/blkLen;
    blkLens = ones(numBlks,1)*blkLen;
end
stIdx = 0;
phErrEst = zeros(numBlks+1, 1);
phErrEst(1) = prevPhErrEst;
for idx = 1:numBlks
    endIdx = stIdx+blkLens(idx);
    winLen = stIdx+1:endIdx;
    buffer = rxPilots(winLen);
    ref = refPilots(winLen);
    % carrier phase error calculation
    phTemp = angle(sum(buffer.*conj(ref)));
    % Unwrapping the phase error using the phase estimate made on the
    % previous pilot block
    phErrEst(idx+1) = prevPhErrEst + alpha*wrapToPi(phTemp-prevPhErrEst);
    prevPhErrEst = phErrEst(idx+1);
    stIdx = endIdx;
end
end
