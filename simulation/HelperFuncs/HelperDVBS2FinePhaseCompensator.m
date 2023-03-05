classdef HelperDVBS2FinePhaseCompensator < matlab.System
    %HelperDVBS2FinePhaseCompensator DVB-S2 fine phase compensator for
    %16 and 32 APSK modulations schemes
    %
    %   Note: This is a helper object and its API and/or functionality
    %   may change in subsequent releases.
    %
    %   HSYNC = HelperDVBS2FinePhaseCompensator creates a carrier phase
    %   synchronizer object, HSYNC, that compensates for carrier phase
    %   offset. The object is designed to correct APSK signals. The object
    %   uses a closed-loop PLL approach to compensate phase offset
    %   generated due to phase noise. The PLL uses a first order loop
    %   filter and the loop filter output is considered as phase error
    %   estimate. The loop filter is reset for every pilot block to avoid
    %   cyclic slip.
    %
    %   Step method syntax:
    %
    %   OUT = step(HSYNC, IN) estimates the carrier phase offset of
    %   the input, IN and returns the corrected signal in OUT. The step
    %   method outputs the phase corrected OUT as the same size and type as
    %   the input.
    %
    %   HelperDVBS2FinePhaseCompensator properties:
    %
    %   NormalizedLoopBandwidth - Loop bandwidth normalized by symbol rate
    %   DataFrameSize           - DVBS2 PL data frame length
    %
    %   References:
    %   [1] E. Casini, R. De Gaudenzi and A. Ginesi: "DVB-S2
    %   modem algorithms design and performance over typical satellite
    %   channels", International Journal on Satellite Communication
    %   Networks, Volume 22, Issue 3.
    %   [2] Umberto Mengali and Aldo N. D'Andrea, Synchronization
    %   Techniques for Digital Receivers. New York: Plenum Press, 1997.
    
    %   Copyright 2020 The MathWorks, Inc.
 
    properties (Nontunable)
        %DataFrameSize Data frame size
        %   Specify the data frame size of the DVBS2 physical layer data
        %   frame as a real positive scalar. The value must be computed
        %   based on the FEC frame type and modulation order used. For
        %   'normal' frame, the value is defined as
        %   64800/log2(ModulationOrder) and for 'short' frame, it is
        %   defined as 16200/log2(ModulationOrder). The default value is
        %   16200 which corresponds to 16APSK normal frame.
        DataFrameSize = 16200;
        %NormalizedLoopBandwidth Normalized loop bandwidth
        %   Specify normalized loop bandwidth as a real positive scalar.
        %   The default value is 3.5e-4. Decreasing the loop bandwidth will
        %   decrease convergence time, but reduces the pull-in range of the
        %   synchronizer. 
        NormalizedLoopBandwidth = 3.5e-4;
    end

  properties (Access = private, Nontunable)
    % APSK modulated symbols are raised to a power to convert the
    % constellation into QPSK
    pPowerFactor
    % Phase value used for rotating the APSK constellation to convert into
    % QPSK
    pPhaseShiftFactor
    % Input data type
    pInputDataType
    % Pilot indices in the PL frame
    pPilotIndices
  end

  properties (Access = private) 
    % Loop filter integrator gain
    pIntegratorGain
    % Digital synthesizer gain
    pDigitalSynthesizerGain
    % Phase error estimate
    pPhase
    % Variable to hold previous input sample
    pPreviousSample
    % Loop filter state variable
    pLoopFilterState
    % Integrator state variable
    pIntegFilterState
  end

  methods
    % Constructor
    function obj = HelperDVBS2FinePhaseCompensator(varargin)
      setProperties(obj,nargin,varargin{:});
    end

    function set.NormalizedLoopBandwidth(obj, value)
      obj.NormalizedLoopBandwidth = value;
    end

    function set.DataFrameSize(obj, value)
        obj.DataFrameSize = value;
    end
  end

  methods (Access=protected)
    % Initial Object Setup
    function setupImpl(obj, input)

      % Save input datatype, needed for reset method
      obj.pInputDataType = class(input);

      % Output initial values
      obj.pPhase = zeros(1,obj.pInputDataType);       % Retain datatype but not complexity.
      obj.pPreviousSample = zeros(1,'like',input);    % Retain datatype and complexity.

      switch obj.DataFrameSize
        case {16200, 4050} % 16APSK
          obj.pPowerFactor = cast(3,obj.pInputDataType);
          obj.pPhaseShiftFactor = cast(0,obj.pInputDataType);
        case {12960, 3240} % 32 APSK
          obj.pPowerFactor = cast(4,obj.pInputDataType);
          obj.pPhaseShiftFactor = cast(0.25,obj.pInputDataType);
      end
      % Get loop gains
      obj.pIntegratorGain = 4*obj.NormalizedLoopBandwidth/(2*(1+2*obj.NormalizedLoopBandwidth));
      % Get pilot indices
      numPilotBlks = floor(obj.DataFrameSize/(90*16));
      if floor(obj.DataFrameSize/(90*16)) == obj.DataFrameSize/(90*16)
          numPilotBlks = numPilotBlks-1;
      end
      [~,temp] = satcom.internal.dvbs.pilotBlock(numPilotBlks);
      obj.pPilotIndices = temp(36:36:end)+90;
      % Invert DDS output to correct not estimate
      obj.pDigitalSynthesizerGain = cast(-1,obj.pInputDataType);
    end

    % Runtime Operation
    function [output, phaseEstimate] = stepImpl(obj, input)

      % Complex inflate
      inputC = complex(input);

      % Copying to local variables for performance
      loopFiltState = obj.pLoopFilterState;
      previousSample = obj.pPreviousSample;

      % Preallocate outputs
      output          = coder.nullcopy(zeros(size(inputC),'like',inputC));
      phaseCorrection = coder.nullcopy(zeros(size(inputC),'like',inputC));

      for k = 1:length(inputC)
          % Transforming an APSK symbol into a QPSK symbol
          phErrInp = (previousSample.^obj.pPowerFactor)*exp(1j*pi*obj.pPhaseShiftFactor);
          % Find phase error
          phErr = imag(phErrInp*(sign(real(phErrInp))-1j*sign(imag(phErrInp))));
          % Phase accumulate and correct
          output(k) = inputC(k)*exp(1i*obj.pPhase);
          % Reset the loop filter every pilot field to avoid cyclic slip
          if any(k == obj.pPilotIndices+1)
              loopFiltState = 0;
          end
          % Loop Filter
          loopFiltOut = loopFiltState+phErr*obj.pIntegratorGain ;
          loopFiltState = loopFiltOut;
          % Direct digital synthesizer (look up table)
          obj.pPhase = obj.pDigitalSynthesizerGain*loopFiltOut;
          phaseCorrection(k) = obj.pPhase;
          previousSample = output(k);
      end

      % Changing sign to convert from correction value to estimate
      phaseEstimate = -real(phaseCorrection);

      %Updating states
      obj.pLoopFilterState = loopFiltState;
      obj.pPreviousSample = complex(previousSample);
    end

    % Reset parameters and objects to initial states
    function resetImpl(obj)
      obj.pLoopFilterState = zeros(1,obj.pInputDataType);
      obj.pIntegFilterState = zeros(1,obj.pInputDataType);
      obj.pPhase = zeros(1,obj.pInputDataType);
      obj.pPreviousSample = complex(zeros(1,obj.pInputDataType));
    end

    % Save object
    function s = saveObjectImpl(obj)
      s = saveObjectImpl@matlab.System(obj);
      if isLocked(obj)
        s.pIntegratorGain = obj.pIntegratorGain;
        s.pDigitalSynthesizerGain = obj.pDigitalSynthesizerGain;
        s.pPhase = obj.pPhase;
        s.pPreviousSample = obj.pPreviousSample;
        s.pInputDataType = obj.pInputDataType;
        s.pLoopFilterState = obj.pLoopFilterState;
        s.pIntegFilterState = obj.pIntegFilterState;
      end
    end

    % Load object
    function loadObjectImpl(obj, s, wasLocked)
      if wasLocked
        obj.pIntegratorGain = s.pIntegratorGain;
        obj.pDigitalSynthesizerGain = s.pDigitalSynthesizerGain;
        obj.pPhase = s.pPhase;
        obj.pPreviousSample = s.pPreviousSample;
        obj.pInputDataType = s.pInputDataType;
        obj.pLoopFilterState = s.pLoopFilterState;
        obj.pIntegFilterState = s.pIntegFilterState;
      end
      % Call the base class method
      loadObjectImpl@matlab.System(obj, s);
    end
  end 

  methods(Static,Access=protected)
    function groups = getPropertyGroupsImpl
        groups = matlab.system.display.Section(...
            'Title', 'Parameters',...
            'PropertyList', {'NormalizedLoopBandwidth', 'DataFrameSize'});
    end
end
end

