% Add LDPC matrices
if ~exist('dvbs2xLDPCParityMatrices.mat','file')
    if ~exist('s2xLDPCParityMatrices.zip','file')
        url = 'https://ssd.mathworks.com/supportfiles/spc/satcom/DVB/s2xLDPCParityMatrices.zip';
        websave('s2xLDPCParityMatrices.zip',url);
        unzip('s2xLDPCParityMatrices.zip');
    end
addpath('s2xLDPCParityMatrices');
end

%% 

s2WaveGen = dvbs2WaveformGenerator("NumInputStreams",1,"MODCOD",6,"RolloffFactor",0.25 ); % QPSK 2/3
disp(s2WaveGen)

%%
numFramesPerStream = 1;                                         % Number of PL frames generated per stream
syncBits = [0 1 0 0 0 1 1 1]';                                  % Sync byte of TS packet (47 HEX)
pktLen = 1496;                                                  % User packet (UP) length without sync bits is 1496    
numPktsPerStream = s2WaveGen.MinNumPackets*numFramesPerStream;  % Number of packets required to fill data field per stream

%%
data =  cell(s2WaveGen.NumInputStreams,1);
for i = 1:s2WaveGen.NumInputStreams
    txRawPkts = randi([0 1],pktLen,numPktsPerStream(i));
    txPkts = [repmat(syncBits,1,numPktsPerStream(i)); txRawPkts];
    data{i} = txPkts(:); 
end

%%
txWaveform = s2WaveGen(data);

%%
BW = 36e6;                                           % Typical satellite channel bandwidth
Fsym = BW/(1+s2WaveGen.RolloffFactor);
plot(abs(txWaveform));

%%
BW = 36e6;                                           % Typical satellite channel bandwidth
Fsym = BW/(1+s2WaveGen.RolloffFactor);
Fsamp = Fsym*s2WaveGen.SamplesPerSymbol;
spectrum = spectrumAnalyzer('SampleRate',Fsamp,TimeSpanSource="property",TimeSpan=2);
spectrum(txWaveform);
release(spectrum);

%% 
data = 2*randi([0 1],1e6,1) - 1;

txfilter = comm.RaisedCosineTransmitFilter

filteredData = txfilter(data);
