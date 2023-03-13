function rxIn = PBNJ_symb_channel(txOut, EbNo, sps, modOrder, codeRate, ...
    JNR, p)
    
    rxIn = zeros(length(txOut),1);

    
    % find power of signal for noise and jammer power
    sig_power = mean(abs(txOut).^2);

    % WGN for noise signal
    EsNodB = convertSNR(EbNo,"ebno","esno", "BitsPerSymbol",log2(modOrder), "CodingRate",codeRate);
    SNR_dB = EsNodB - 10*log10(sps);
    No = sig_power/db2pow(SNR_dB);

    % WGN for PBNJ
    JNR_mag = db2mag(JNR);
    Jo = JNR_mag*No;
    jammer_power = Jo/p;

    jammer = wgn(sps,1,pow2db(sqrt(2)*jammer_power), 'complex');

    % Passs through awgn channel
    rxIn = awgn(txOut,SNR_dB,'measured');
    % 1 symbol transmitted per hop
    for n=1:sps:length(txOut)
        isJammed = binornd(1,p); % bernoulli distribution
        if isJammed
%             jammer = wgn(sps,1,pow2db(sqrt(2)*jammer_power), 'complex');
            rxIn(n:n+sps-1) = rxIn(n:n+sps-1) + jammer;
        end
    end
  
    fprintf("EbNo = %f dB, EsNo = %f dB, JNR = %f, p = %f\n",EbNo, EsNodB, JNR, p);

end