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
simParams.EbNodB = 1.5;                                  % Energy per bit to noise ratio
% simParams.p = 0.4;                                     % fraction of bandwidth jammed
simParams.JNR = -20;                                   % jammer to noise ratio (dB)
simParams.onlySOF = true;

%% Compute FER as a function of EbNo

p_values = 0:0.1:1; % range of fraction of band jammed values to test
num_trials = 30;

fer_values = zeros(1, length(p_values)); % averaged fer values
pctPLH_values = zeros(1, length(p_values));
pctPLF_values = zeros(1, length(p_values));

fer_t = 0;
fer_s = 0;

for n=1:length(p_values)
    for i = 1:num_trials
        fprintf('trial number: %d/%d\n',i,num_trials);
        simParams.p = p_values(n);
        [fer_t,pctPLH_values(n),pctPLF_values(n)] = DVBS2_FER_calculator(cfgDVBS2,simParams);
        fer_s = fer_s + fer_t;
    end
    fer_values(n) = fer_s/num_trials;
    fer_s = 0;
end



%% Plot FER as a function of EbNo
save_FER = true;

[clean_p, clean_fer_values] = clean_ER(p_values,fer_values);


if save_FER
    p_path = sprintf('data/FER_data/p-modcod%d-%d-%d-%1.1f.mat',cfgDVBS2.MODCOD,num_trials,simParams.numFrames,simParams.EbNodB);
    FER_path = sprintf('data/FER_data/FER-modcod%d-%d-%d-%1.1f.mat',cfgDVBS2.MODCOD,num_trials,simParams.numFrames,simParams.EbNodB);
    save(p_path, "clean_p");
    save(FER_path,"clean_fer_values");
end



%% actual data
pctPLH_int = 0:0.05:1;
% FER_int = interp1(pctPLH_values,fer_values,pctPLH_int,"linear");

plot(pctPLH_values,fer_values,'o')
% semilogy(EbNo,fer_values,'o',pctPLH_int,FER_int,':.')
hold on
grid
legend('Estimated FER')
xlabel('p (fraction of bandwidth jammed)')
ylabel('Frame Error Rate')
hold off

%% cleaned data
pctPLH_int = 0:0.01:1;
FER_int = interp1(clean_p,clean_fer_values,pctPLH_int,"linear",'extrap');

plot(clean_p,clean_fer_values,'o',pctPLH_int,FER_int,':.')
hold on
grid
legend('Estimated FER')
xlabel('p (fraction of bandwidth jammed)')
ylabel('Frame Error Rate')
% hold off


%% Theoretical FER in PBNJ symbol by symbol

% linear Jammer to noise ratio
% p = simParams.p;
p = simParams.p;
JNR = simParams.JNR; % decible value
JNR = db2mag(JNR); % convert to magnitude

S = load(p_path);
p_N = S.clean_p;

S = load(FER_path);
FER_N = S.clean_fer_values;


% fer_NJ = BER_NJ(clean_p, clean_fer_values, JNR, p);




%% Plot FER_NJ
% semilogy(clean_p,fer_NJ,'x-')
% hold on
% grid
% legend('Estimated FER')
% xlabel('Eb/No (dB)')
% ylabel('Frame Error Rate')

% Plot original FER_N

plot(p_N,FER_N,'x-')
hold on
grid
legend('Estimated FER')
xlabel('Eb/No (dB)')
ylabel('Frame Error Rate')