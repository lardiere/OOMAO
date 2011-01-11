classdef telescope < telescopeAbstract
    % Create a telescope object
    %
    % sys = telescope(D) creates a telescope object from the telescope diameter D
    %
    % sys = telescope(D,...) creates a telescope object from the
    % above parameter and from optionnal parameter-value pair arguments. The
    % optionnal parameters are those of the telescopeAbstract class.
    %
    % Example:
    % tel = telescope(8); An 8m diameter telescope
    %
    % tel = telescope(8,'obstructionRatio',0.14,'fieldOfViewInArcmin',2,'resolution',64); 
    % An 8m diameter telescope with an 14% central obstruction, a 2 arcmin
    % fov and a pupil sampled with 64x64 pixels
    % Displaying the pupil:
    % imagesc(tel.pupil)
    % The pupil logical mask is given by
    % tel.pupilLogical
    %
    % A telescope object can be combined with an atmosphere object to
    % define a volume of turbulence above the telescope within its
    % field-of--view:
    % atm = atmosphere(photometry.V,0.15,30,...
    %     'altitude',4e3,...
    %     'fractionnalR0',1,...
    %     'windSpeed',15,...
    %     'windDirection',0);
    % tel = telescope(8,'fieldOfViewInArcmin',2,'resolution',64,'samplingTime',1/500); 
    % The telescope-atmosphere object is built by adding the atmosphere to
    % the telescope:
    % tel = tel + atm; 
    % figure, imagesc(tel)
    % The frozen-flow or Taylor motion of the phase screen is created by
    % updating the telescope object:
    % +tel;
    % The phase screen(s) are moved of an amount depending on the
    % samplingTime and the wind vector parameters.
    % The geometric propagation of a star through the atmosphere to the
    % telescope pupil is done as followed
    % ngs = source;
    % ngs = ngs.*tel;
    % figure, imagesc(ngs.phase), axis square xy, colorbar
    % At anytime the atmosphere can be removed from the telescope:
    % tel = tel - atm;
    %
    % See also telescopeAbstract, atmosphere and source
    
    properties
        % wind shifted turbulence sampling time
        samplingTime;
        % phase listener
        phaseListener;
        % telescope tag
        tag = 'TELESCOPE';
    end
    
    properties (Dependent)
        % optical aberrations seen by the telescope
        opticalAberration;
    end
    
    properties (Dependent , SetAccess = private)
        % telescope pupil mask
        pupil;
    end
    
    properties (Access=private)
        atm;
        innerMask;
        outerMask;
        A;
        B;
        windVx;
        windVy;
        count;
        mapShift;
        nShift;
        x;
        y;
        imageHandle;
        layerSampling;
        sampler;
        log;
        p_pupil;
    end
    
    methods
        
        %% Constructor
        function obj = telescope(D,varargin)
            p = inputParser;
            p.addRequired('D', @isnumeric);
            p.addParamValue('obstructionRatio', 0, @isnumeric);
            p.addParamValue('fieldOfViewInArcsec', [], @isnumeric);
            p.addParamValue('fieldOfViewInArcmin', [], @isnumeric);
            p.addParamValue('resolution', [], @isnumeric);
            p.addParamValue('samplingTime', [], @isnumeric);
            p.addParamValue('opticalAberration', [], @(x) isa(x,'atmosphere'));
            p.parse(D,varargin{:});
            obj = obj@telescopeAbstract(D,...
                'obstructionRatio',p.Results.obstructionRatio,...
                'fieldOfViewInArcsec',p.Results.fieldOfViewInArcsec,...
                'fieldOfViewInArcmin',p.Results.fieldOfViewInArcmin,...
                'resolution',p.Results.resolution);
            obj.samplingTime = p.Results.samplingTime;
            obj.log = logBook.checkIn(obj);
            obj.opticalAberration = p.Results.opticalAberration;
            display(obj)
        end
        
        %% Destructor
        function delete(obj)
            if isa(obj.opticalAberration,'atmosphere')
                add(obj.log,obj,'Deleting atmosphere layer slabs!')
                for kLayer=1:obj.atm.nLayer
                    obj.atm.layer(kLayer).phase = [];
                end
            end
            checkOut(obj.log,obj)
        end
        
        function display(obj)
            %% DISPLAY Display object information
            %
            % display(obj) prints information about the atmosphere+telescope object
            
            display(obj.atm)
            fprintf('___ %s ___\n',obj.tag)
            if obj.obstructionRatio==0
                fprintf(' %4.2fm diameter full aperture',obj.D)
            else
                fprintf(' %4.2fm diameter with a %4.2f%% central obstruction',...
                    obj.D,obj.obstructionRatio*100)
            end
            fprintf(' with %5.2fm^2 of light collecting area;\n',obj.area)
            if obj.fieldOfView~=0
                fprintf(' the field-of-view is %4.2farcmin;',...
                    obj.fieldOfView*constants.radian2arcmin)
            end
            if ~isempty(obj.resolution)
                fprintf(' the pupil is sampled with %dX%d pixels',...
                    obj.resolution,obj.resolution)
            end
            if obj.fieldOfView~=0 || ~isempty(obj.resolution)
                fprintf('\n')
            end
            fprintf('----------------------------------------------------\n')
            
        end

        %% Get and Set the pupil
        function pupil = get.pupil(obj)
            pupil = obj.p_pupil;
            if isempty(pupil) && ~isempty(obj.resolution)
                pupil = utilities.piston(obj.resolution);
                if obj.obstructionRatio>0
                    pupil = pupil - ...
                        utilities.piston(...
                        round(obj.resolution.*obj.obstructionRatio),...
                        obj.resolution);
                end
                obj.p_pupil = pupil;
            end
        end
        
        %% Set/Get for opticalAberration property
        function set.opticalAberration(obj,val)
            obj.atm = val;
            if ~isempty(val) && isa(val,'atmosphere')
                obj.phaseListener = addlistener(obj.atm.layer(1),'phase','PostSet',...
                    @(src,evnt) obj.imagesc );
                obj.phaseListener.Enabled = false;
                if ~isempty(obj.samplingTime)
                    init(obj);
                end
            end
        end        
        function out = get.opticalAberration(obj)
            out = obj.atm;
        end
        
        function varargout = update(obj)
            %% UPDATE Phase screens deplacement
            %
            % update(obj) moves the phase screens of each layer of one time
            % step in the direction of the corresponding wind vectors
            %
            % obj = update(obj) moves the phase screens and returns the
            % object
            
            
            %             disp(' (@telescope) > Layer translation')
            
            if ~isempty(obj.atm) % uncorrelated phase screens
                
                if isinf(obj.samplingTime)
                    
                    for kLayer=1:obj.atm.nLayer
                        
                        obj.atm.layer(kLayer).phase = ...
                            fourierPhaseScreen(slab(obj.atm,kLayer));
                        
                    end
                    
                elseif ~(obj.atm.nLayer==1 && (obj.atm.layer.windSpeed==0 || isempty(obj.atm.layer.windSpeed) ) )
                    %                 disp('HERE')
                    for kLayer=1:obj.atm.nLayer
                        
                        pixelLength = obj.atm.layer(kLayer).D./(obj.atm.layer(kLayer).nPixel-1); % sampling in meter
                        % 1 pixel increased phase sampling vector
                        u0 = (-1:obj.atm.layer(kLayer).nPixel).*pixelLength;
                        %                     [xu0,yu0] = meshgrid(u0);
                        % phase sampling vector
                        u = (0:obj.atm.layer(kLayer).nPixel-1).*pixelLength;
                        
                        % phase displacement in meter
                        leap = [obj.windVx(kLayer) obj.windVy(kLayer)].*(obj.count(kLayer)+1).*obj.samplingTime;
                        % phase displacement in pixel
                        pixelLeap = leap/pixelLength;
                        
                        notDoneOnce = true;
                        
                        %                     fprintf(' >>> Layer #%d: nShift=%d ; count=%d ; pixelLeap=(%4.2f,%4.2f) ; pixelLength=%4.2f ; leap=(%4.2f,%4.2f)\n',...
                        %                        kLayer, obj.nShift(kLayer), obj.count(kLayer) , pixelLeap(1) , pixelLeap(2) , pixelLength , leap)
                        %                     fprintf(' ------> Starting while loop\n');
                        
                        while any(pixelLeap>1) || notDoneOnce
                            notDoneOnce = false;
                            
                            if obj.count(kLayer)==0
                                %                             fprintf(' ------>      : expanding!\n')
                                % 1 pixel around phase increase
                                Z = obj.atm.layer(kLayer).phase(obj.innerMask{kLayer}(2:end-1,2:end-1));
                                X = obj.A{kLayer}*Z + obj.B{kLayer}*randn(size(obj.B{kLayer},2),1);
                                obj.mapShift{kLayer}(obj.outerMask{kLayer})  = X;
                                obj.mapShift{kLayer}(~obj.outerMask{kLayer}) = obj.atm.layer(kLayer).phase(:);
                            end
                            
                            % phase displacement (not more than 1 pixel)
                            step   = min(abs(leap),pixelLength).*sign(leap);
                            xShift = u - step(1);
                            yShift = u - step(2);
                            obj.atm.layer(kLayer).phase ...
                                = spline2({u0,u0},obj.mapShift{kLayer},{yShift,xShift});
                            %                         obj.atm.layer(kLayer).phase ...
                            %                                = interp2(xu0,yu0,obj.mapShift{kLayer},xShift',yShift,'*nearest');
                            
                            leap = leap - step;
                            pixelLeap = leap/pixelLength;
                            
                            %                         fprintf(' ------>      : count=%d ; pixelLeap=(%4.2f,%4.2f) ; step=(%4.2f,%4.2f)\n',...
                            %                             obj.count(kLayer) , pixelLeap(1) , pixelLeap(2), step)
                            
                        end
                        
                        obj.count(kLayer)       = rem(obj.count(kLayer)+1,obj.nShift(kLayer));
                        
                    end
                    
                end
                
            end
            
            if nargout>0
                varargout{1} = obj;
            end
        end
        function varargout = uplus(obj)
            %% UPLUS + Update operator
            %
            % +obj updates the atmosphere phase screens
            %
            % obj = +obj returns the telescope object
            
            % by swapping random states, the atmosphere maintains an
            % independant random data stream from all other processes.
            
            global_state = randn('state');      % Save global random state
            randn('state',obj.atm.randn_state); % Load atmospheric random state
            
            update(obj)
            
            obj.atm.randn_state = randn('state'); % Save atmospheric random state
            randn('state',global_state);          % Load global random state
            if nargout>0
                varargout{1} = obj;
            end
        end
        
        function obj = plus(obj,otherObj)
            %% + Add a component to the telescope
            %
            % obj = obj + otherObj adds an other object to the telescope
            % object 
            
            obj.opticalAberration = otherObj;
        end
        
        function obj = minus(obj,otherObj)
            %% - Remove a component from the telescope
            %
            % obj = obj - otherObj removes an other object to the telescope
            % object 
            
            if isa(obj.opticalAberration,class(otherObj))
            obj.opticalAberration = [];
            else
                warning('cougar:telescope:minus',...
                    'The current and new objet must be from the same class (current: %s ~= new: %s)',...
                    class(obj.opticalAberration),class(otherObj))
            end
        end
        
        function relay(obj,srcs)
            %% RELAY Telescope to source relay
            %
            % relay(obj,srcs) writes the telescope amplitude and phase into
            % the properties of the source object(s)
            
            if isempty(obj.resolution) % Check is resolution has been set
                if isscalar(srcs(1).amplitude) % if the src is not set either, do nothing
                    return
                else % if the src is set, set the resolution according to src wave resolution
                    obj.resolution = length(srcs(1).amplitude);
                end
            end
            
            nSrc = numel(srcs);
            for kSrc=1:nSrc % Browse the srcs array
                src = srcs(kSrc);
                % Set mask and pupil first
                src.mask      = obj.pupilLogical;
                if isempty(src.nPhoton)
                    src.amplitude = obj.pupil;
                else
                    src.amplitude = obj.pupil.*sqrt(obj.samplingTime*src.nPhoton.*obj.area/sum(obj.pupil(:))); 
                end
                out = 0;
                if ~isempty(obj.atm) % Set phase if an atmosphere is defined
                    if obj.fieldOfView==0 && isNgs(src)
                        out = out + sum(cat(3,obj.atm.layer.phase),3);
                    else
                        atm_m           = obj.atm;
                        nLayer          = atm_m.nLayer;
                        altitude_m      = [atm_m.layer.altitude];
                        sampler_m       = obj.sampler;
                        phase_m         = { atm_m.layer.phase };
                        R_              = obj.R;
                        layerSampling_m = obj.layerSampling;
                        srcDirectionVector1 = src.directionVector(1);
                        srcDirectionVector2 = src.directionVector(2);
                        srcHeight = src.height;
                        out = zeros(size(src.amplitude,1),size(src.amplitude,2),nLayer);
                        parfor kLayer = 1:nLayer
                            height = altitude_m(kLayer);
                            sampling = { layerSampling_m{kLayer} , layerSampling_m{kLayer} };
                            if height==0
                                out(:,:,kLayer) = phase_m{kLayer};
                            else
                                layerR = R_*(1-height./srcHeight);
                                u = sampler_m*layerR;
                                xc = height.*srcDirectionVector1;
                                yc = height.*srcDirectionVector2;
                                out(:,:,kLayer) = spline2(sampling,phase_m{kLayer},{u-yc,u-xc});
                            end
                        end
                        out = sum(out,3);
                    end
                    out = (obj.atm.wavelength/src.wavelength)*out; % Scale the phase according to the src wavelength
                end
                src.phase = fresnelPropagation(src,obj) + out;
                src.timeStamp = src.timeStamp + obj.samplingTime;
            end
            
        end
                 
        function out = otf(obj, r)
            %% OTF Telescope optical transfert function
            %
            % out = otf(obj, r) Computes the telescope optical transfert function
            
%             out = zeros(size(r));
            if obj.obstructionRatio ~= 0
                out = pupAutoCorr(obj.D) + pupAutoCorr(obj.obstructionRatio*obj.D) - ...
                    2.*pupCrossCorr(obj.D./2,obj.obstructionRatio*obj.D./2);
            else
                out = pupAutoCorr(obj.D);
            end
            out = out./(pi*obj.D*obj.D.*(1-obj.obstructionRatio*obj.obstructionRatio)./4);
            
            if isa(obj.opticalAberration,'atmosphere')
                out = out.*phaseStats.otf(r,obj.opticalAberration);
            end
            
            function out1 = pupAutoCorr(D)
                
                index       = r <= D;
                red         = r(index)./D;
                out1        = zeros(size(r));
                out1(index) = D.*D.*(acos(red)-red.*sqrt((1-red.*red)))./2;
                
            end            
            
            function out2 = pupCrossCorr(R1,R2)
                
                out2 = zeros(size(r));
                
                index       = r <= abs(R1-R2);
                out2(index) = pi*min([R1,R2]).^2;
                
                index       = (r > abs(R1-R2)) & (r < (R1+R2));
                rho         = r(index);
                red         = (R1*R1-R2*R2+rho.*rho)./(2.*rho)/(R1);
                out2(index) = out2(index) + R1.*R1.*(acos(red)-red.*sqrt((1-red.*red)));
                red         = (R2*R2-R1*R1+rho.*rho)./(2.*rho)/(R2);
                out2(index) = out2(index) + R2.*R2.*(acos(red)-red.*sqrt((1-red.*red)));
                
            end
            
        end
         
        function out = psf(obj,f)
            %% PSF Telescope point spread function
            %
            % out = psf(obj, f) computes the telescope point spread function
            
            if isa(obj.opticalAberration,'atmosphere')
                fun = @(u) 2.*pi.*quadgk(@(v) psfHankelIntegrandNested(v,u),0,obj.D);
                out = arrayfun( fun, f);
            else
                out   = ones(size(f)).*pi.*obj.D.^2.*(1-obj.obstructionRatio.^2)./4;
                index = f~=0;
                u = pi.*obj.D.*f(index);
                surface = pi.*obj.D.^2./4;
                out(index) = surface.*2.*besselj(1,u)./u;
                if obj.obstructionRatio>0
                    u = pi.*obj.D.*obj.obstructionRatio.*f(index);
                    surface = surface.*obj.obstructionRatio.^2;
                    out(index) = out(index) - surface.*2.*besselj(1,u)./u;
                end
                out = abs(out).^2./(pi.*obj.D.^2.*(1-obj.obstructionRatio.^2)./4);
                
            end
            function y = psfHankelIntegrandNested(x,freq)
                y = x.*besselj(0,2.*pi.*x.*freq).*otf(obj,x);
            end
        end
             
        function out = fullWidthHalfMax(obj)
            %% FULLWIDTHHALFMAX Full Width at Half the Maximum evaluation
            %
            % out = fullWidthHalfMax(a) computes the FWHM of a telescope
            % object. Units are m^{-1}. To convert it in arcsecond,
            % multiply by the wavelength then by radian2arcsec.
            
            if isa(obj.opticalAberration,'atmosphere')
                x0 = [0,2/min(obj.D,obj.opticalAberration.r0)];
            else
                x0 = [0,2/obj.D];
            end
            [out,fval,exitflag] = fzero(@(x) psf(obj,abs(x)./2) - psf(obj,0)./2,x0,optimset('TolX',1e-9));
            if exitflag<0
                warning('cougar:telescope:fullWidthHalfMax',...
                    'No interval was found with a sign change, or a NaN or Inf function value was encountered during search for an interval containing a sign change, or a complex function value was encountered during the search for an interval containing a sign change.')
            end
            out = abs(out);
        end
        
        function varargout = footprintProjection(obj,zernModeMax,src)
            nSource = length(src);
            P = cell(obj.atm.nLayer,nSource);
            obj.log.verbose = false;
            for kSource = 1:nSource
                fprintf(' @(telescope) > Source #%2d - Layer #00',kSource)
                for kLayer = 1:obj.atm.nLayer
                    fprintf('\b\b%2d',kLayer)
                    obj.atm.layer(kLayer).zern = ...
                        zernike(1:zernModeMax,'resolution',obj.atm.layer(kLayer).nPixel);
                    conjD = obj.atm.layer(kLayer).D;
                    delta = obj.atm.layer(kLayer).altitude.*...
                        tan(src(kSource).zenith).*...
                        [cos(src(kSource).azimuth),sin(src(kSource).azimuth)];
                    delta = delta*2/conjD;
                    alpha = conjD./obj.D;
                    P{kLayer,kSource} = smallFootprintExpansion(obj.atm.layer(kLayer).zern,delta,alpha);
                    varargout{1} = P;
                end
                fprintf('\n')
            end
            obj.log.verbose = true;
%             if nargout>1
%                 o = linspace(0,2*pi,101);
%                 varargout{2} = cos(o)./alpha + delta(1);
%                 varargout{3} = sin(o)./alpha + delta(2);
%             end
        end

        function varargout = imagesc(obj,varargin)
            %% IMAGESC Phase screens display
            %
            % imagesc(obj) displays the phase screens of all the layers
            %
            % imagesc(obj,'PropertyName',PropertyValue) specifies property
            % name/property value pair for the image plot
            %
            % h = imagesc(obj,...) returns the image graphic handle
            
            if all(~isempty(obj.imageHandle)) && all(ishandle(obj.imageHandle))
                for kLayer=1:obj.atm.nLayer
                    n = size(obj.atm.layer(kLayer).phase,1);
                    pupil = utilities.piston(n,'type','logical');
                    map = (obj.atm.layer(kLayer).phase - mean(obj.atm.layer(kLayer).phase(pupil))).*pupil;
                    set(obj.imageHandle(kLayer),'Cdata',map);
                end
            else
                src = [];
                if nargin>1 && isa(varargin{1},'source')
                    src = varargin{1};
                    varargin(1) = [];
                end
                [n1,m1] = size(obj.atm.layer(1).phase);
                pupil = utilities.piston(n1,'type','logical');
                map = (obj.atm.layer(1).phase - mean(obj.atm.layer(1).phase(pupil))).*pupil;
                obj.imageHandle(1) = image([1,m1],[1,n1],map,...
                    'CDataMApping','Scaled',varargin{:});
                hold on
                o = linspace(0,2*pi,101)';
                xP = obj.resolution*cos(o)/2;
                yP = obj.resolution*sin(o)/2;
                plot(xP+(n1+1)/2,yP+(n1+1)/2,'color',ones(1,3)*0.8)
                    if ~isempty(src)
                        kLayer = 1;
                        for kSrc=1:numel(src)
                            xSrc = src(kSrc).directionVector(1).*...
                                obj.atm.layer(kLayer).altitude.*...
                                obj.atm.layer(kLayer).nPixel/...
                                obj.atm.layer(kLayer).D;
                            ySrc = src(kSrc).directionVector(2).*...
                                obj.atm.layer(kLayer).altitude.*...
                                obj.atm.layer(kLayer).nPixel/...
                                obj.atm.layer(kLayer).D;
                            plot(xSrc+xP+(n1+1)/2,ySrc+yP+(n1+1)/2,'color',ones(1,3)*0.8)
                        end
                    else
                        plot(xP+(n1+1)/2,yP+(n1+1)/2,'k:')
                    end
                text(m1/2,n1+0.5,...
                    sprintf('%.1fkm: %.1f%%\n%.2fm - %dpx',...
                    obj.atm.layer(1).altitude*1e-3,...
                    obj.atm.layer(1).fractionnalR0*100,...
                    obj.atm.layer(1).D,...
                    obj.atm.layer(1).nPixel),...
                    'HorizontalAlignment','Center',...
                    'VerticalAlignment','Bottom')
                n = n1;
                offset = 0;
                for kLayer=2:obj.atm.nLayer
                    [n,m] = size(obj.atm.layer(kLayer).phase);
                    pupil = utilities.piston(n,'type','logical');
                    offset = (n1-n)/2;
                    map = (obj.atm.layer(kLayer).phase - mean(obj.atm.layer(kLayer).phase(pupil))).*pupil;
                    obj.imageHandle(kLayer) = imagesc([1,m]+m1,[1+offset,n1-offset],map);
                    if ~isempty(src)
                        for kSrc=1:numel(src)
                            xSrc = src(kSrc).directionVector(1).*...
                                obj.atm.layer(kLayer).altitude.*...
                                obj.atm.layer(kLayer).nPixel/...
                                obj.atm.layer(kLayer).D;
                            ySrc = src(kSrc).directionVector(2).*...
                                obj.atm.layer(kLayer).altitude.*...
                                obj.atm.layer(kLayer).nPixel/...
                                obj.atm.layer(kLayer).D;
                            plot(xSrc+xP+m1+m/2,ySrc+yP+(n1+1)/2,'color',ones(1,3)*0.8)
                        end
                    else
                        plot(xP+m1+m/2,yP+(n1+1)/2,'k:')
                    end
                    text(m1+m/2,(n1+1+m)/2,...
                        sprintf('%.1fkm: %.1f%%\n%.2fm - %dpx',...
                        obj.atm.layer(kLayer).altitude*1e-3,...
                        obj.atm.layer(kLayer).fractionnalR0*100,...
                        obj.atm.layer(kLayer).D,...
                        obj.atm.layer(kLayer).nPixel),...
                        'HorizontalAlignment','Center',...
                        'VerticalAlignment','Bottom')
                    m1 = m + m1;
                end
                hold off
                set(gca,'xlim',[1,m1],'ylim',[1+offset,n-offset],'visible','off')
                axis xy equal tight
                colorbar('location','southOutside')
            end
            if nargout>0
                varargout{1} = obj.imageHandle;
            end
        end
        
    end
    
    
    methods (Access=private)
        
        function obj = init(obj)
            %% INIT
            
            nInner = 2;
            obj.sampler = linspace(-1,1,obj.resolution);
            add(obj.log,obj,'Initializing phase screens making parameters:')
            obj.log.verbose = false;
            do = obj.D/(obj.resolution-1);
            for kLayer=1:obj.atm.nLayer
                if isempty(obj.atm.layer(kLayer).phase)
                    D = obj.D + 2*obj.atm.layer(kLayer).altitude.*tan(0.5*obj.fieldOfView);
                    nPixel = 1 + round(D./do);
                    obj.atm.layer(kLayer).D = do*(nPixel-1);
%                     nPixel = round(1 + (obj.resolution-1)*D./Do);
                    obj.atm.layer(kLayer).nPixel = nPixel;
                    obj.layerSampling{kLayer}  = D*0.5*linspace(-1,1,nPixel);
                    % ---------
                    fprintf('   Layer %d:\n',kLayer)
                    fprintf('            -> Computing initial phase screen (D=%3.2fm,n=%dpx) ...',D,nPixel)
                    m_atm = slab(obj.atm,kLayer);
                    obj.atm.layer(kLayer).phase = fourierPhaseScreen(m_atm,D,nPixel);
                    fprintf('  Done \n')
                    % ---------
                    obj.outerMask{kLayer} = ...
                        ~utilities.piston(nPixel,nPixel+2,...
                        'shape','square','type','logical');
                    obj.innerMask{kLayer} =  ...
                        ~( obj.outerMask{kLayer} | ...
                        utilities.piston(nPixel-2*nInner,nPixel+2,...
                        'shape','square','type','logical') );
                    fprintf('            -> # of elements for the outer maks: %d and for the inner mask %d\n',...
                        sum(obj.outerMask{kLayer}(:)),sum(obj.innerMask{kLayer}(:)));
                    fprintf('            -> Computing matrix A and B for layer %d: ',kLayer)
                    [u,v] = meshgrid( (0:nPixel+1).*D/(nPixel-1) );
                    % ---------
                    innerZ = complex(u(obj.innerMask{kLayer}),v(obj.innerMask{kLayer}));
                    fprintf('ZZt ...')
                    ZZt = phaseStats.covarianceMatrix(innerZ,m_atm);
                    % ---------
                    outerZ = complex(u(obj.outerMask{kLayer}),v(obj.outerMask{kLayer}));
                    fprintf('\b\b\b, ZXt ...')
                    ZXt = phaseStats.covarianceMatrix(innerZ,outerZ,m_atm);
                    clear innerZ
                    % ---------
                    obj.A{kLayer}   = ZXt'/ZZt;
                    % ---------
                    clear ZZt
                    fprintf('\b\b\b, XXt ...')
                    XXt = phaseStats.covarianceMatrix(outerZ,m_atm);
                    clear outerZ
                    % ---------
                    BBt = XXt - obj.A{kLayer}*ZXt;
                    clear XXt ZXt
                    obj.B{kLayer} = chol(BBt,'lower');
                    fprintf('  Done \n')
                    % ---------
                    obj.windVx(kLayer) = m_atm.layer.windSpeed.*cos(m_atm.layer.windDirection);
                    obj.windVy(kLayer) = m_atm.layer.windSpeed.*sin(m_atm.layer.windDirection);
                    obj.count(kLayer) = 0;
                    obj.mapShift{kLayer} = zeros(nPixel+2);
                    pixelStep = [obj.windVx obj.windVy].*obj.samplingTime*(nPixel-1)/D;
                    obj.nShift(kLayer) = max(floor(min(1./pixelStep)),1);
                    u = (0:nPixel+1).*D./(nPixel-1);
                    %                 [u,v] = meshgrid(u);
                    obj.x{kLayer} = u;
                    obj.y{kLayer} = u;%v;
                end
            end
            obj.log.verbose = true;
        end
        
    end
    
    methods (Static)
        function sys = demo(action)
            sys = telescope(2.2e-6,0.8,30,25,...
                'altitude',[0,10,15].*1e3,...
                'fractionnalR0',[0.7,0.2,0.1],...
                'windSpeed',[10,5,15],...
                'windDirection',[0,pi/4,pi/2],...
                'fieldOfViewInArcMin',2,...
                'resolution',60*15,...
                'samplingTime',1/500);
            %             sys = telescope(2.2e-6,0.8,10,25,...
            %                 'altitude',10.*1e3,...
            %                 'fractionnalR0',1,...
            %                 'windSpeed',10,...
            %                 'windDirection',0,...
            %                 'fieldOfViewInArcMin',1,...
            %                 'resolution',60,...
            %                 'samplingTime',1e-3);
            if nargin>0
                update(sys);
                sys.phaseListener.Enabled = true;
                imagesc(sys)
                while true
                    update(sys);
                    drawnow
                end
            end
        end
        
        function sys = demoSingleLayer
            sys = telescope(2.2e-6,0.8,10,25,...
                'altitude',10e3,...
                'fractionnalR0',1,...
                'windSpeed',10,...
                'windDirection',0,...
                'fieldOfViewInArcMin',2,...
                'resolution',256,...
                'samplingTime',1/500);
        end
    end
    
end

function F = spline2(x,v,xi)
%2-D spline interpolation

% % Determine abscissa vectors
% varargin{1} = varargin{1}(1,:);
% varargin{2} = varargin{2}(:,1).';
%
% %
% % Check for plaid data.
% %
% xi = varargin{4}; yi = varargin{5};
% xxi = xi(1,:); yyi = yi(:,1);
%
% %     F = splncore(varargin(2:-1:1),varargin{3},{yyi(:).' xxi},'gridded');
%     x = varargin(2:-1:1);
%     v = varargin{3};
%     xi = {yyi(:).' xxi};
% gridded spline interpolation via tensor products
nv = size(v);
d = length(x);
values = v;
sizeg = zeros(1,d);
for i=d:-1:1
    values = spline(x{i},reshape(values,prod(nv(1:d-1)),nv(d)),xi{i}).';
    sizeg(i) = length(xi{i});
    nv = [sizeg(i), nv(1:d-1)];
end
F = reshape(values,sizeg);

    function output = spline(x,y,xx)
        % disp('Part 1')
        % tStart = tic;
        output=[];
        
        sizey = size(y,1);
        n = length(x); yd = prod(sizey);
        
        % Generate the cubic spline interpolant in ppform
        
        dd = ones(yd,1); dx = diff(x); divdif = diff(y,[],2)./dx(dd,:);
        b=zeros(yd,n);
        b(:,2:n-1)=3*(dx(dd,2:n-1).*divdif(:,1:n-2)+dx(dd,1:n-2).*divdif(:,2:n-1));
        x31=x(3)-x(1);xn=x(n)-x(n-2);
        b(:,1)=((dx(1)+2*x31)*dx(2)*divdif(:,1)+dx(1)^2*divdif(:,2))/x31;
        b(:,n)=...
            (dx(n-1)^2*divdif(:,n-2)+(2*xn+dx(n-1))*dx(n-2)*divdif(:,n-1))/xn;
        dxt = dx(:);
        c = spdiags([ [x31;dxt(1:n-2);0] ...
            [dxt(2);2*[dxt(2:n-1)+dxt(1:n-2)];dxt(n-2)] ...
            [0;dxt(2:n-1);xn] ],[-1 0 1],n,n);
        
        % sparse linear equation solution for the slopes
        mmdflag = spparms('autommd');
        spparms('autommd',0);
        s=b/c;
        spparms('autommd',mmdflag);
        % toc(tStart)
        % construct piecewise cubic Hermite interpolant
        % to values and computed slopes
        %    disp('Part pwch')
        %    tStart = tic;
        pp = pwch(x,y,s,dx,divdif); pp.dim = sizey;
        % toc(tStart)
        
        % end
        
        %      disp('Part ppval')
        %  tStart = tic;
        output = ppval(pp,xx);
        % toc(tStart)
        
        
        
    end

end