%% Add LDPC matrices
if ~exist('dvbs2xLDPCParityMatrices.mat','file')
    if ~exist('s2xLDPCParityMatrices.zip','file')
        url = 'https://ssd.mathworks.com/supportfiles/spc/satcom/DVB/s2xLDPCParityMatrices.zip';
        websave('s2xLDPCParityMatrices.zip',url);
        unzip('s2xLDPCParityMatrices.zip');
    end
addpath('s2xLDPCParityMatrices');
end

%% 

cfgDVBS2.StreamFormat = "TS";
cfgDVBS2.FECFrame = "normal";
cfgDVBS2.MODCOD = 6;                             % QPSK 2/3
cfgDVBS2.DFL = 42960;
cfgDVBS2.ScalingMethod = "Unit average power"; % Only use in APSK
cfgDVBS2.RolloffFactor = 0.35;
cfgDVBS2.HasPilots = true;
cfgDVBS2.SamplesPerSymbol = 2;

simParams.sps = cfgDVBS2.SamplesPerSymbol;             % Samples per symbol
simParams.numFrames = 10;                              % Number of frames to be processed
simParams.chanBW = 36e6;                               % Channel bandwidth in Hertz
% simParams.EbNodB = 2.1;
simParams.p = 0.4;                                     % fraction of bandwidth jammed
simParams.JNR = -20;                                   % jammer to noise ratio (dB)

%% Compute BER as a function of EbNo

EbNo = 1:0.05:2; % range of bit snr values to test

ber_values = zeros(1, length(EbNo));

for n=1:length(ber_values)
    simParams.EbNodB = EbNo(n);
    ber_values(n) = DVBS2_BER_calculator(cfgDVBS2,simParams);
end



%% Plot BER as a function of EbNo

[clean_EbNo, clean_ber_values] = clean_BER(EbNo,ber_values);
% save('EbNo-modcod6-1-2', "clean_EbNo");
% save('BER-modcod6-1-2',"clean_ber_values");


%% actual data
EbNo_int = 1:0.01:2;
BER_int = interp1(EbNo,ber_values,EbNo_int,"linear");

semilogy(EbNo,ber_values,'o',EbNo_int,BER_int,':.')
hold on
grid
legend('Estimated BER')
xlabel('Eb/No (dB)')
ylabel('Bit Error Rate')
hold off

%% cleaned data
EbNo_int = 0:0.01:3;
BER_int = interp1(clean_EbNo,clean_ber_values,EbNo_int,"linear",'extrap');

semilogy(clean_EbNo,clean_ber_values,'o',EbNo_int,BER_int,':.')
hold on
grid
legend('Estimated BER')
xlabel('Eb/No (dB)')
ylabel('Bit Error Rate')
% hold off


%% Theoretical BER in PBNJ symbol by symbol

% linear Jammer to noise ratio
% p = simParams.p;
p = simParams.p;
JNR = simParams.JNR; % decible value
JNR = db2mag(JNR); % convert to magnitude

S = load("EbNo-modcod6-1-2.mat");
EbNo_N = S.clean_EbNo;

S = load("BER-modcod6-1-2.mat");
BER_N = S.clean_ber_values;


ber_NJ = BER_NJ(clean_EbNo, clean_ber_values, JNR, p);




%% Plot BER_NJ
semilogy(clean_EbNo,ber_NJ,'x-')
hold on
grid
legend('Estimated BER')
xlabel('Eb/No (dB)')
ylabel('Bit Error Rate')

% Plot original BER_N

semilogy(EbNo_N,BER_N,'x-')
hold on
grid
legend('Estimated BER')
xlabel('Eb/No (dB)')
ylabel('Bit Error Rate')
