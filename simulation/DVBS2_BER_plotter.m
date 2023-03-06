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
simParams.EbNodB = 2.1;

%% Compute BER as a function of EbNo

EbNo = 1:0.05:2; % range of bit snr values to test

ber_values = zeros(1, length(EbNo));

for n=1:length(ber_values)
    simParams.EbNodB = EbNo(n);
    ber_values(n) = DVBS2_BER_calculator(cfgDVBS2,simParams);
end

%% Plot BER
semilogy(EbNo,ber_values,'x-')
hold on
grid
legend('Estimated BER')
xlabel('Eb/No (dB)')
ylabel('Bit Error Rate')