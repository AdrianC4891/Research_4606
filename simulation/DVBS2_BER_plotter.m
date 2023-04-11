%% Add LDPC matrices
if ~exist('data/s2xLDPCParityMatrices/dvbs2xLDPCParityMatrices.mat','file')
    if ~exist('data/s2xLDPCParityMatrices/s2xLDPCParityMatrices.zip','file')
        url = 'https://ssd.mathworks.com/supportfiles/spc/satcom/DVB/s2xLDPCParityMatrices.zip';
        websave('data/s2xLDPCParityMatrices/s2xLDPCParityMatrices.zip',url);
        unzip('data/s2xLDPCParityMatrices/s2xLDPCParityMatrices.zip');
    end
else
    addpath('data/s2xLDPCParityMatrices');
end

%% 

cfgDVBS2.StreamFormat = "TS";
cfgDVBS2.FECFrame = "normal";
cfgDVBS2.MODCOD = 1;                             % QPSK 1/4
cfgDVBS2.DFL = 15928;% 42960; for QPSK 2/3
cfgDVBS2.ScalingMethod = "Unit average power"; % Only use in APSK
cfgDVBS2.RolloffFactor = 0.35;
cfgDVBS2.HasPilots = true;
cfgDVBS2.SamplesPerSymbol = 2;

simParams.sps = cfgDVBS2.SamplesPerSymbol;             % Samples per symbol
simParams.numFrames = 10;                              % Number of frames to be processed
simParams.chanBW = 36e6;                               % Channel bandwidth in Hertz
% simParams.EbNodB = 2.1;
simParams.p = 0.2;                                     % fraction of bandwidth jammed
simParams.JNR = -40;                                   % jammer to noise ratio (dB)
simParams.onlySOF = false;

%% Compute BER as a function of EbNo

EbNo_min = -0.3;
EbNo_max = 0.8;
sp = 0.1;

EbNo = EbNo_min:sp:EbNo_max; % range of bit snr values to test

ber_values = zeros(1, length(EbNo));

for n=1:length(ber_values)
    simParams.EbNodB = EbNo(n);
    ber_values(n) = DVBS2_BER_calculator(cfgDVBS2,simParams);
end



%% Plot BER as a function of EbNo
save_BER = false;

[clean_EbNo, clean_ber_values] = clean_ER(EbNo,ber_values);

EbNo_path = sprintf('data/BER_data/EbNo-modcod%d-%d-%d.mat',cfgDVBS2.MODCOD,min(EbNo),max(EbNo));
BER_path = sprintf('data/BER_data/BER-modcod%d-%d-%d.mat',cfgDVBS2.MODCOD,min(EbNo),max(EbNo));

if save_BER
    save(EbNo_path, "clean_EbNo");
    save(BER_path,"clean_ber_values");
end



%% actual data
EbNo_int = EbNo_min:0.01:EbNo_max;
BER_int = interp1(EbNo,ber_values,EbNo_int,"linear");

semilogy(EbNo,ber_values,'o',EbNo_int,BER_int,':.')
hold on
grid
legend('Estimated BER')
xlabel('Eb/No (dB)')
ylabel('Bit Error Rate')
hold off

%% cleaned data
EbNo_int = -1:0.01:1;
BER_int = interp1(clean_EbNo,clean_ber_values,EbNo_int,"linear",'extrap');

semilogy(clean_EbNo,clean_ber_values,'o',EbNo_int,BER_int,':.')
hold on
grid
legend('Estimated BER')
xlabel('Eb/No (dB)')
ylabel('Bit Error Rate')
% hold off


%% Theoretical BER in PBNJ symbol by symbol

EbNo_noJ_path = sprintf('data/BER_data/EbNo-modcod%d-%d-%d.mat',cfgDVBS2.MODCOD,-1,1);
BER_noJ_path = sprintf('data/BER_data/BER-modcod%d-%d-%d.mat',cfgDVBS2.MODCOD,-1,1);

% linear Jammer to noise ratio
% p = simParams.p;
p = simParams.p;
JNR = simParams.JNR; % decible value
JNR = db2mag(JNR); % convert to magnitude

S = load(EbNo_noJ_path);
EbNo_N = S.clean_EbNo;

S = load(BER_noJ_path);
BER_N = S.clean_ber_values;


ber_NJ = BER_NJ(EbNo_N, BER_N,EbNo_max,sp, JNR, p);




%% Plot BER_NJ
semilogy(EbNo_N,ber_NJ,'x-')
hold on
grid
legend('theoretical BER with PBNJ')
xlabel('Eb/No (dB)')
ylabel('Bit Error Rate')

semilogy(clean_EbNo,clean_ber_values,'x-')
hold on
grid
legend('simulated BER with PBNJ')
xlabel('Eb/No (dB)')
ylabel('Bit Error Rate')

% Plot original BER_N

semilogy(EbNo_N,BER_N,'x-')
hold on
grid
legend('No PBNJ BER')
xlabel('Eb/No (dB)')
ylabel('Bit Error Rate')
