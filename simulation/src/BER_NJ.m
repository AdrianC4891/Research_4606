function Pb_NJ = BER_NJ(EbNo_Arr, BER_N_Arr, JNR, p)

    % compute BER of jammed symbols
    Eb_J = EbNo_Arr - 10*log(1 + JNR/p);
    Pb_J = interp1(EbNo_Arr,BER_N_Arr,Eb_J,'linear', 'extrap');

    % bound the array at 0 and 1
    Pb_J(Pb_J<0) = 0;
    Pb_J(Pb_J>0.1) = 0.1;

    % compute 
    Pb_NJ = p*Pb_J + (1-p)*BER_N_Arr;

end