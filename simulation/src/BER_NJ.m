function Pb_NJ = BER_NJ(EbNo_Arr, BER_N_Arr, EbNo_max,spacing, JNR, p)

    % compute BER of jammed symbols
    EbNo_J = EbNo_Arr - 10*log(1 + JNR/p);
    
%     EbNo_extra = max(EbNo_J):spacing:EbNo_max;
%     EbNo_J = [EbNo_J, EbNo_extra];

    Pb_J = interp1(EbNo_Arr,BER_N_Arr,EbNo_J,'linear', 'extrap');

    % bound the array at 0 and 1
    Pb_J(Pb_J<0) = 0;
    Pb_J(Pb_J>0.1) = max(BER_N_Arr);

    % compute 
    Pb_NJ = p*Pb_J + (1-p)*BER_N_Arr;

end