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

%% Compute FER as a function of EbNo

EbNo = 1:0.05:2; % range of bit snr values to test

fer_values = zeros(1, length(EbNo));

for n=1:length(fer_values)
    simParams.EbNodB = EbNo(n);
    [fer_values(n),~,~] = DVBS2_FER_calculator(cfgDVBS2,simParams);
end



%% Plot FER as a function of EbNo
save_FER = true;

[clean_EbNo, clean_fer_values] = clean_ER(EbNo,fer_values);


if save_FER
    EbNo_path = sprintf('data/FER_data/EbNo-modcod%d-%d-%d.mat',cfgDVBS2.MODCOD,min(EbNo),max(EbNo));
    FER_path = sprintf('data/FER_data/FER-modcod%d-%d-%d.mat',cfgDVBS2.MODCOD,min(EbNo),max(EbNo));
    save(EbNo_path, "clean_EbNo");
    save(FER_path,"clean_fer_values");
end



%% actual data
EbNo_int = 1:0.01:2;
FER_int = interp1(EbNo,fer_values,EbNo_int,"linear");

semilogy(EbNo,fer_values,'o',EbNo_int,FER_int,':.')
hold on
grid
legend('Estimated FER')
xlabel('Eb/No (dB)')
ylabel('Frame Error Rate')
hold off

%% cleaned data
EbNo_int = 0:0.01:3;
FER_int = interp1(clean_EbNo,clean_fer_values,EbNo_int,"linear",'extrap');

semilogy(clean_EbNo,clean_fer_values,'o',EbNo_int,FER_int,':.')
hold on
grid
legend('Estimated FER')
xlabel('Eb/No (dB)')
ylabel('Bit Error Rate')
% hold off


%% Theoretical FER in PBNJ symbol by symbol

% linear Jammer to noise ratio
% p = simParams.p;
p = simParams.p;
JNR = simParams.JNR; % decible value
JNR = db2mag(JNR); % convert to magnitude

S = load(EbNo_path);
EbNo_N = S.clean_EbNo;

S = load(FER_path);
FER_N = S.clean_fer_values;


fer_NJ = BER_NJ(clean_EbNo, clean_fer_values, JNR, p);




%% Plot FER_NJ
semilogy(clean_EbNo,fer_NJ,'x-')
hold on
grid
legend('Estimated FER')
xlabel('Eb/No (dB)')
ylabel('Frame Error Rate')

% Plot original FER_N

semilogy(EbNo_N,FER_N,'x-')
hold on
grid
legend('Estimated FER')
xlabel('Eb/No (dB)')
ylabel('Frame Error Rate')