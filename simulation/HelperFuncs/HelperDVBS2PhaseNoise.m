classdef (StrictDefaults)HelperDVBS2PhaseNoise < matlab.System
    %HelperDVBS2PhaseNoise Apply phase noise to a complex, baseband
    %DVB-S2/S2X signal
    %   PHNOISE = HelperDVBS2PhaseNoise creates a phase noise System
    %   object, PHNOISE. This object applies phase noise with the specified
    %   level at the specified frequency offset to a complex, baseband
    %   input signal.
    %
    %   Note: This is a helper object and its API and/or functionality may
    %   change in subsequent releases.
    %
    %   PHNOISE = HelperDVBS2PhaseNoise(Name,Value) creates a phase noise
    %   object, PHNOISE, with the specified property Name set to the
    %   specified Value. You can specify additional name-value pair
    %   arguments in any order as (Name1,Value1,...,NameN,ValueN).
    %
    %   PHNOISE = HelperDVBS2PhaseNoise(LEVEL,OFFSET,SAMPLERATE,Name,Value)
    %   creates a phase noise object, PHNOISE, with the Level property set
    %   to LEVEL, the FrequencyOffset property set to OFFSET, the
    %   SampleRate property set to SAMPLERATE, and other specified property
    %   Names set to the specified Values. LEVEL, OFFSET, and SAMPLERATE
    %   are value-only arguments. To specify a value-only argument, you
    %   must also specify all preceding value-only arguments. You can
    %   specify name-value pair arguments in any order.
    %
    %   Step method syntax:
    %
    %   Y = step(PHNOISE,X) adds phase noise with the specified level, at
    %   the specified frequency offset, to the input X and returns the
    %   result in Y. X must be a complex scalar or column vector of data
    %   type double or single. The step method outputs, Y, with the same
    %   data type and dimensions as the input.
    %
    %   System objects may be called directly like a function instead of
    %   using the step method. For example, y = step(obj, x) and y = obj(x)
    %   are equivalent.
    %
    %   HelperDVBS2PhaseNoise methods:
    %
    %   step      - Apply phase noise to input signal
    %   release   - Allow property value and input characteristics
    %              changes
    %   clone     - Create phase noise object with same property values
    %   isLocked  - Locked status (logical)
    %
    %   HelperDVBS2PhaseNoise properties:
    %
    %   Level           - Phase noise level (dBc/Hz)
    %   FrequencyOffset - Frequency offset (Hz)
    %   SampleRate      - Sample rate (Hz)
    %   RandomStream    - 'Global stream' or 'mt19937ar with seed'
    %   Seed            - Initial seed

    %   Copyright 2020-2021 The MathWorks, Inc.
   
    properties (Nontunable)
        %Level Phase noise level (dBc/Hz)
        %   Specify the phase noise level in decibels relative to carrier per
        %   Hertz (dBc/Hz) as a negative, real scalar or vector of data type
        %   double. The default is [-80 -100].
        Level = [-80 -100]
        %FrequencyOffset Frequency offset (Hz)
        %   Specify the frequency offset in Hertz as a positive, real scalar or
        %   increasing vector of data type double. The default is [2000 20000].
        FrequencyOffset = [2000 20000]
        %SampleRate Sample rate (Hz)
        %   Specify the sample rate in samples per second as a positive, real
        %   scalar of data type double.  The default is 1e6.
        SampleRate = 1e6
        %RandomStream Random number source
        %   Specify the source of random number stream as one of 'Global stream'
        %   | 'mt19937ar with seed'.  If RandomStream is set to 'Global stream',
        %   the current global random number stream is used for normally
        %   distributed random number generation.  If RandomStream is set to
        %   'mt19937ar with seed', the mt19937ar algorithm is used for normally
        %   distributed random number generation, in which case the reset method
        %   re-initializes the random number stream to the value of the Seed
        %   property. The default value of this property is 'Global stream'.
        RandomStream = 'Global stream'
        %Seed Initial seed
        %   Specify the seed as a positive double precision integer-valued
        %   scalar less than 2^32.  The default is 2137.  This property is
        %   relevant when the RandomStream property is set to 'mt19937ar with
        %   seed'.
        Seed = 2137
    end

    properties(Access = private, Nontunable)
        cDFilt         % IIR, time domain FIR, or frequency domain FIR filter
        % used to shape phase noise
        pRNGStream     % white Gaussian noise state
        pInputDataType % input data type
    end

    properties(Constant, Hidden)
        RandomNumGenerator = 'mt19937ar';
        RandomStreamSet = matlab.system.StringSet(...
            {'Global stream', 'mt19937ar with seed'});
    end

    methods
        % CONSTRUCTOR
        function obj = HelperDVBS2PhaseNoise(varargin)
            coder.allowpcode('plain');
            setProperties(obj, nargin, varargin{:}, ...
                'Level', 'FrequencyOffset', 'SampleRate');
        end

        % Set properties validation
        function set.Level(obj, value)
            obj.Level = value;
        end

        function set.FrequencyOffset(obj, value)
            obj.FrequencyOffset = value;
        end

        function set.SampleRate(obj, value)
            obj.SampleRate = value;
        end

        function set.Seed(obj, value)
            obj.Seed = value;
        end
    end

    methods(Access = protected)

        function flag = isInactivePropertyImpl(obj, prop)
            flag = ...
                strcmp(prop, 'Seed') && strcmp(obj.RandomStream, 'Global stream');
        end

        function flag = isInputSizeMutableImpl(~,~)
            flag = true;
        end


        function setupImpl(obj, x)
            obj.pInputDataType = class(x);
            setupRNG(obj);
            % Create filter System object
            num = getFilterCoeffs ...
                (obj.Level, obj.FrequencyOffset, obj.SampleRate);
            obj.cDFilt = dsp.FrequencyDomainFIRFilter(num, ...
                'Method','overlap-add');
        end

        function y = stepImpl(obj, x)
            % Generate Gaussian white noise
            numRows = size(x, 1);
            numCols = 1;
            if strcmp(obj.RandomStream, 'Global stream')
                noise = (randn(numCols, numRows, obj.pInputDataType)).';
            else
                noise = ...
                    (randn(obj.pRNGStream, numCols, numRows, obj.pInputDataType)).';
            end
            % Filter noise to the specified shape
            filtNoise = step(obj.cDFilt, noise);
            % Convert amplitude noise to phase noise and apply to the input.
            % Output and input are the same data type
            y = x.*exp(1i*filtNoise);
        end

        function resetImpl(obj)
            resetRNG(obj);
            reset(obj.cDFilt);
        end

        function releaseImpl(obj)
            release(obj.cDFilt);
        end

        function s = saveObjectImpl(obj)
            % Public properties handled automatically
            s = saveObjectImpl@matlab.System(obj);
            if isLocked(obj)
                s.cDFilt = matlab.System.saveObject(obj.cDFilt);
                s.pRNGStream = obj.pRNGStream;
                s.pInputDataType = obj.pInputDataType;
            end
        end

        function loadObjectImpl(obj, s, wasLocked)
            if wasLocked
                % Public properties handled automatically
                % Objects saved prior to R2014b used an instance of deprecated
                % dsp.DigitalFilter. Turn off deprecation warning to avoid warnings
                % during MAT file load
                if strcmp(s.cDFilt.ClassNameForLoadTimeEval,'dsp.DigitalFilter')
                    obj.cDFilt = dsp.FIRFilter(...
                        'Structure','Direct form transposed',...
                        'Numerator',s.cDFilt.ChildClassData.Numerator);
                else
                    obj.cDFilt = matlab.System.loadObject(s.cDFilt);
                end
                % New private properties since R2019a
                if isfield(s, 'pRNGStream')
                    if ~isempty(s.pRNGStream)
                        obj.pRNGStream = ...
                            RandStream(obj.RandomNumGenerator, 'Seed', obj.Seed);
                        obj.pRNGStream.State = s.pRNGStream.State;
                    end
                    obj.pInputDataType = s.pInputDataType;
                end
            end
            % Call the base class method
            loadObjectImpl@matlab.System(obj, s);
        end
        
    end

    methods(Access = private) % RNG related methods
        function setupRNG(obj)
            if ~strcmp(obj.RandomStream, 'Global stream')
                if isempty(coder.target)
                    obj.pRNGStream = RandStream(...
                        obj.RandomNumGenerator, 'Seed', obj.Seed);
                else
                    obj.pRNGStream = coder.internal.RandStream(...
                        obj.RandomNumGenerator, 'Seed', obj.Seed);
                end
            end
        end

        function resetRNG(obj)
            % Reset random number generator if it is not global stream
            if ~strcmp(obj.RandomStream, 'Global stream')
                reset(obj.pRNGStream, obj.Seed);
            end
        end
        
    end

    methods(Static, Access = protected)
        function group = getPropertyGroupsImpl
            % Define property section(s) for System block dialog
            pRandStream = matlab.system.display.internal.Property(...
                'RandomStream', ...
                'IsGraphical', false, ...
                'UseClassDefault', false, ...
                'Default', 'mt19937ar with seed');
            
            group = matlab.system.display.Section( ...
                'PropertyList', ...
                {'Level', 'FrequencyOffset', 'SampleRate', pRandStream, 'Seed'});
        end
    end
end

function num = getFilterCoeffs(levelDB, freqSpec, Fs)

% Allowed maximum number of taps for filter design
%  nTapsMAX = 2^16;

% Minimum number of taps to allow for stable results
nTapsMIN = 2^6;

% Ideal frequency resolution - It must handle half the lowest specified
% frequency offset and the minimum difference in the specified frequency
% vector
df1 = 0.5*freqSpec(1);
df2 = min(diff([0 freqSpec]));
df = min(df1,df2);

% Number of required taps, accounting for maximum
nTaps = max(2^nextpow2((Fs/2) / df), nTapsMIN);  % Number of taps
% nTaps = min(nTaps, nTapsMAX);

df = (Fs/2) / nTaps;  % Update the frequency resolution
% for nTaps power of 2
normFreq = (0:nTaps)/nTaps;  % Normalized frequency vector
freq = normFreq * Fs/2;  % Actual frequency offset
freq(1) = freq(2)/100;  % Avoid a low frequency of 0
freqSpec = [df freqSpec Fs/2];  % Include the frequency
% resolution and Fs/2 as the first
% and last frequencies respectively

% Extrapolate a phase noise level by assuming a 1/f^3
% characteristic from the lowest frequency spec point down to df
levelNew = -3 * (log10(freqSpec(1)) - log10(freqSpec(2))) + levelDB(1);
levelDB = [levelNew levelDB levelDB(end)];

% Interpolate to determine amplitude values at the generated frequency
% points. Flatten the response at 0 Hz. amplSpecDB represents the
% ideal/desired frequency response of the filter.
amplSpecDB = interp1(log10(freqSpec), levelDB, log10(freq), 'linear');
amplSpecDB(1) = levelDB(1);

% Account for cases where interp1 may have erroneously extrapolated and
% returned NaNs.
amplSpecDB(isnan(amplSpecDB)) = amplSpecDB(1);
amplSpecLin = 10.^(amplSpecDB/20);  % Convert to linear

% Design the FIR filter with the given nTaps
errorDB = 1000; % Initial error
tolerance = 1;    % Acceptable error in dB
% nTaps = min(nTaps,nTapsMAX);        % Ensure we do not exceed the max
%  while(errorDB > tolerance && nTaps <= nTapsMAX)
nTapsRef = nTaps;
while(errorDB > tolerance)
    % FIR response for a specified number of taps
    d = fdesign.arbmag('N,F,A',nTaps,normFreq,amplSpecLin);
    hd = getFilter(d, nTaps);
    t = zerophase(hd,nTaps);
    ampActDB = 20*log10([t;t(end)]);
    fList = d.Frequencies*Fs/2;
    fListNew = 0:df:fList(end);
    if numel(ampActDB) > numel(fList)
        ampActDB = ampActDB(1:nTaps/nTapsRef:end);
    end
    % Interpolate amplitudes of ideal filter response to compare
    amplRealDB = interp1(fList,ampActDB,fListNew);
    % Calculate dB error at all computed frequencies
    errorListDB = abs(amplSpecDB - amplRealDB);
    errorDB = max(errorListDB);
    % Update parameters for arbitrary filter response
    nTaps = nTaps*2;
end

% Multiply numerator coefficients by sqrt(Fs) to account for the dBc/Hz
% specification
num = hd.Numerator * sqrt(Fs);

end
function hd = getFilter(inp, nTaps)

hspecs = fspecs.sbarbmag;
hspecs.FilterOrder = nTaps;
hspecs.Frequencies = inp.Frequencies;
hspecs.Amplitudes = inp.Amplitudes;

this = fmethod.freqsamparbmag;
this.Window = 'hann';
[N,F,A,P,nfpts] = validatespecs(hspecs);

% Determine if the filter is real
isreal = true;
if F(1)<0, isreal = false; end

% Interpolate magnitudes and phases on regular grid
nfft = min(max(2^nextpow2(N+1),max(2^nextpow2(nfpts),1024)));
[~,aa,pp] = interp_on_regular_grid(F,A,P,nfft,isreal);

% Build the Fourier Transform
H = aa.*exp(1i*pp);

% Inverse Fourier transform
if isreal
    % Force Hermitian property of Fourier Transform
    H = [H conj(H(nfft:-1:2))];
    b = ifft(H,'symmetric');
else
    b = ifft(fftshift(H),'nonsymmetric');
end

% Truncate filter
b = b(1:N+1);

% Apply Window
b = applywindow(this,b,N);

hd = dsp.FIRFilter('Numerator',b);
end
function [ff,aa,pp] = interp_on_regular_grid(F,A,P,nfft,isreal)
% Interpolate magnitudes and phases on regular grid

if isreal
    % Use nfft+1 points for the positive frequencies (including nyquist):
    % [dc 1 2 ... nyquist]
    ff = linspace(F(1),F(end),nfft+1);
else
    ff = linspace(F(1),F(end),nfft);
end
aa = interp1(F,A,ff);
pp = interp1(F,P,ff);
end
