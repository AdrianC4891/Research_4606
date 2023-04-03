function [EbNo,BER] = clean_ER(EbNo_or, BER_or)

    BER_zeros = find(BER_or <= 0);
    
    EbNo = EbNo_or;
    EbNo(BER_zeros) = [];

    BER = BER_or;
    BER(BER_zeros) = [];

end
