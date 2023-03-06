function syncIndex = HelperDVBS2FrameSync(rxSymb)
%HelperDVBS2FrameSync Detect the start of DVB-S2/S2X physical layer frame
%
%   Note: This is a helper function and its API and/or functionality may
%   change in subsequent releases.
%
%   SYNCINDEX = HelperDVBS2FrameSync(RXSYMB) detects the start of physical
%   layer frame, SYNCINDEX by performing differential correlation on the
%   received symbols, RXSYMB. Physical layer header consisting of start of
%   frame (SOF) and physical layer signalling code (PLSC) is searched for
%   detecting the start of frame. The 32 bit PLSC code is either repeated
%   or flipped and repeated based on the presence or absence of pilots.
%   This property is used while performing differential correlation. For
%   very low signal to noise ratio and in presence of high carrier
%   frequency offset and phase noise, perform this frame detection on
%   multiple frames before finalizing the start index.
%
%   References:
%   E. Casini, R. De Gaudenzi and A. Ginesi: "DVB-S2
%   modem algorithms design and performance over typical satellite
%   channels", International Journal on Satellite Communication
%   Networks, Volume 22, Issue 3.

%   Copyright 2020 The MathWorks, Inc.

% PL header uses pi/2-BPSK. The differential correlated sequence for PLSC
% code (64 symbols) with pilots on and including the scrambling.
refPLSC = 1j*[-1 1 1 -1 -1 -1 1 -1 -1 1 1 1 1 1 -1 -1 -1 -1 1 1 -1 1 1 ...
    -1 1 -1 1 -1 1 1 -1 -1];
% Start of frame is a 26 bit sequence. The differential correlated sequence
% for SOF.
refSOF = 1j*[1 1 1 1 -1 -1 -1 -1 1 -1 -1 -1 1 -1 -1 1 1 -1 1 1 -1 1 -1 -1 1];

% Each slot is considered as 90 symbols in a PL frame.
winLen = 90;
inpLen = length(rxSymb);
corrVal = zeros(inpLen-winLen+1,1);
for k = 1:inpLen-winLen+1
    buff = rxSymb(k:k+winLen-1);
    diffOut = buff(1:winLen-1).*conj(buff(2:winLen));
    cSOF = sum(diffOut(1:25).*conj(refSOF(:)));
    % Based on PLSC generation properties, alternate values are considered.
    cPLSC = sum(diffOut(27:2:end).*conj(refPLSC(:))); 
    corrVal(k) = abs(cSOF+cPLSC);
end
   maxVal = max(corrVal);
   syncIndex = find(corrVal/maxVal > 0.75, 2);
end