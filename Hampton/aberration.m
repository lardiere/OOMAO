classdef aberration < handle
    % Create a class that defines an aberration
    % Possible use is inserting non-common path aberrations in the science and/or WFS path

    properties
        % zernike object
        zern;
        % number of modes in the aberration
        nModes;
        % the width (in pixels) of the beam
        resolution;
        % the width (in pixels) of the optic or aberration (can be much
        % larger than the beam width)
        aberrationWidth;
        % object tag
        tag;
        
        rotationAngle;
        
        horizontalDisplacement;
        
        verticalDisplacement;
        
        phaseUnit;
    end
    properties (Dependent, SetObservable=true)
        % magnitude of modes
        coefs;
        phaseAberration;
    end
    properties (Access=private)
        p_phaseAberration;
        p_rowStart;
        p_colStart;
        log;
    end
    methods
        %% Constructor
        function obj = aberration(varargin)
            p = inputParser;
            p.addParamValue('nModes',10, @isnumeric);
            p.addParamValue('resolution',90, @isnumeric);
            p.addParamValue('aberrationWidth',90, @isnumeric);
            p.addParamValue('tag', 'ABERRATION', @isstring);
            p.addParamValue('rotationAngle',0, @isnumeric);
            p.addParamValue('horizontalDisplacement',0, @isnumeric);
            p.addParamValue('verticalDisplacement',0, @isnumeric);
            p.addParamValue('phaseUnit', 10^-6, @isnumeric);
            p.parse(varargin{:});
            
            obj.nModes                  = p.Results.nModes;
            obj.resolution              = p.Results.resolution;
            obj.aberrationWidth         = p.Results.aberrationWidth;
            obj.tag                     = p.Results.tag;
            obj.rotationAngle           = p.Results.rotationAngle;
            obj.horizontalDisplacement  = p.Results.horizontalDisplacement;
            obj.verticalDisplacement    = p.Results.verticalDisplacement;
            obj.phaseUnit               = p.Results.phaseUnit;
            obj.zern                    = zernike(1:obj.nModes,'resolution',obj.aberrationWidth);

            obj.p_rowStart = floor((obj.aberrationWidth-obj.resolution)/2)+1;
            obj.p_colStart = obj.p_rowStart;
            
            obj.log = logBook.checkIn(obj);
            display(obj)
        end
        %% Destructor
        function delete(obj)
            delete(obj.zern)
            %checkOut(obj.log,obj)
        end
        %% Display
        function display(obj)
            fprintf('___ %s ___\n',obj.tag)
            fprintf(' %d Zernike modes in aberration\n ',obj.nModes)
            fprintf('%dX%d pixels defined for aberration\n',obj.aberrationWidth,obj.aberrationWidth)
            fprintf('%dX%d pixels defined for beam\n',obj.resolution,obj.resolution)
            fprintf('----------------------------------------------------\n')
        end
        %% Set/Get the magnitude of the modes.
        function out = get.coefs(obj)
            if isempty(obj.zern.c)
                obj.zern.\obj.p_phaseAberration; %calculates Zernike coefs from phase
            end
            out = obj.zern.c;
        end
        function set.coefs(obj,val)
            %Setting magnitudes updates the aberration phase screen
            val = val(:);
            obj.zern.c = val;
            obj.p_phaseAberration = reshape(obj.zern.modes*val,obj.aberrationWidth,obj.aberrationWidth);
        end
        %% Set
        function out = get.phaseAberration(obj)
            if isempty(obj.p_phaseAberration)
                % if the phase aberration is not set yet, make it zero. 
                obj.coefs = zeros(obj.nModes,1);
            end
            out = obj.p_phaseAberration;
            
        end
        function set.phaseAberration(obj,val)
            % use this if you want to force a phase screen and later
            % calculate the coefs from this screen.
            obj.p_phaseAberration = val;
            obj.zern.c = [];
        end
        function relay(obj,src)
            %% RELAY deformable mirror to source relay
            %
            % relay(obj,srcs) writes the deformableMirror amplitude and
            % phase into the properties of the source object(s)
            
            nSrc       = numel(src);
            wavenumber = 2*pi/src(1).wavelength;
            phase      = obj.zernAberration;
            % Misalignments ------------------
            phase = -2*phase*wavenumber*obj.phaseUnit;
            if obj.rotationAngle ~= 0 || obj.horizontalDisplacement ~= 0 || obj.verticalDisplacement ~= 0
                phase = rotateDisplace(phase,...
                    obj.rotationAngle, obj.horizontalDisplacement, obj.verticalDisplacement, ...
                    'rowStart', obj.p_rowStart, 'colStart', obj.p_colStart, ...
                    'outRows', obj.resolution, 'outCols', obj.resolution);
                src.amplitude(isnan(phase)) = 0;
                phase(isnan(phase)) = 0;
            else
                phase = phase(obj.p_startRow:(obj.p_startRow+obj.resolution-1),...
                              obj.p_startCol:(obj.p_startCol+obj.resolution-1));
            end
            % Currently assuming perfect alignment in its position along
            % optical axis.
            
            
            nPhase     = size(obj.p_modeMags,2);
            if nPhase>nSrc
                for kSrc = 1:nSrc
                    src(kSrc).phase = phase;
                    src(kSrc).amplitude = 1;
                end
            else
                for kSrc = 1:nSrc
                    src(kSrc).phase = phase(:,:,min(kSrc,nPhase));
                    src(kSrc).amplitude = 1;
                end
            end
        end
    end
end