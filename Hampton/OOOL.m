% Much of the following code is copied from Rodolphe Conan's example
% "adaptiveOpticsHowTo.m". His comments have been removed here and can
% still be found there. Comments in this code show where my program differ
% from his.
%
% The challenge of this program is to show that I can program a woofer
% tweeter system with the tools developed by Dr. Conan.
%
% Peter Hampton, August 4, 2010

repeatable = true;
CL = true;


if initialize
    initialize = false;
randn('state',2);
atm = atmosphere(photometry.V,0.15,30,...
    'altitude', 0, ... %[0,4,10]*1e3,...
    'fractionnalR0', 1, ... %[0.7,0.25,0.05],...
    'windSpeed', 10,... [5,10,20],...
    'windDirection', 0); %[0,pi/4,pi]);
nLenslet = 15;

nPx_Lenslet = 6;

sampleTime = 1/100;

% nPx is entirely dependant on the choice of the number of lenslets and the
% choice of the number of pixels per lenslet. Attempted nLenslet = 31 but
% that is prohibitively computationally expensive.

nPx = nPx_Lenslet*nLenslet;

tel = telescope(3.6,...
    'fieldOfViewInArcMin',2.5,...
    'resolution',nPx,...
    'samplingTime',1/100);

ngs = source('wavelength',photometry.J,'height',90000,'magnitude',[]);

tel.focalDistance = ngs.height;

wfs = shackHartmann(nLenslet,nPx,0.5);

ngs = ngs.*tel;
ngs = ngs*wfs;

setValidLenslet(wfs)

+wfs;

wfs.referenceSlopes = wfs.slopes;

+wfs;

tmbif = influenceFunction('monotonic',25/100);

wmbif = influenceFunction('monotonic',25/100);

nActuator = nLenslet + 1;

% Woofer (wm) is chosen to be 8 x 8. The tweeter is tm. These replace the
% single instance of dm.

wmvAct = ones(8);
wmvAct(1,[1 2 7 8]) = 0;
wmvAct(8,[1 2 7 8]) = 0;
wmvAct(2,[1 8]) = 0;
wmvAct(7,[1 8]) = 0;
wmvAct = logical(wmvAct);

wm = deformableMirror(8,...
    'modes',wmbif,...
    'resolution',nPx,...
    'validActuator',wmvAct); % 

tm = deformableMirror(nActuator,...
    'modes',tmbif,...
    'resolution',nPx,...
    'validActuator',wfs.validActuator,...
    'distortionTau', sampleTime,...
    'distortionSaturation',0.03,...
    'distortionConstant',0.02,...
    'sampleTime',sampleTime);

stroke = ngs.wavelength/2;

tm.coefs = eye(tm.nValidActuator)*stroke;

wm.coefs = eye(wm.nValidActuator)*stroke;



% Leave the tm flat and project each woofer actuator onto the wfs to obtain
% the woofer's interaction matrix

ngs=ngs.*tel;
ngs=ngs*wm;
ngs=ngs*wfs;

wmInteractionMatrix = wfs.slopes./stroke;

% Leave the wm flat and project each tweeter actuator onto the wfs to obtain
% the tweeter's interaction matrix

ngs=ngs.*tel;
ngs=ngs*tm;
ngs=ngs*wfs;

tmInteractionMatrix = wfs.slopes./stroke;

[U,S,V]=svd(tmInteractionMatrix);
s=diag(S);

iS = diag(1./s(s > 0.1*s(1)));
[nS,nC] = size(tmInteractionMatrix);
iS(nS,nC) = 0;

tmRecon = V*iS'*U';

[Utm,S,Vwm] = svd(tmRecon*wmInteractionMatrix);

Utm = Utm(:,1:wm.nValidActuator);
Sinv = diag(1./diag(S));

tel=tel+atm;
zern = zernike(1:21,'resolution',nPx);
phase0 = atm.layer.phase;
end



wm.coefs = 0;
tm.coefs = 0;

g = 0.5;
%     ngs=ngs.*+tel;  
    ngs=ngs.*wm*tm*wfs;
    ngs_image = fftshift(abs(fft2(ngs.amplitude.*exp(1i*0*ngs.phase))));
    peakSpot = max(max(ngs_image));
    nSamples = 2^8;
    inMag = randn(1,nSamples);
    inZern = zeros(zern.nMode,nSamples);
    outMag = zeros(size(Utm,2),nSamples);
    outZern = zeros(zern.nMode,nSamples);
    strehl = zeros(1,nSamples);
    lestrehl = zeros(1,nSamples);
    longexposure = 0*ngs_image;
    perfectimage = ngs_image;
    mode = 1;
    fprintf('%4d:',1)
    start_science_camera = 20;

    state = zeros(size(tm.coefs,1),2);
     if repeatable
         atm.randn_state = 7;
         atm.layer.phase = phase0;
%         randn('state',7);
     end
%     state = randn('state');
    tm.verticalTilt = 0;
for kIteration = 1:nSamples
    tm.horizontalTilt = TiltAmplitude*cos(2*pi*pi*sampleTime*k);
    %     figure(1)
    wm.coefs = Vwm(:,mode)*Sinv(mode,mode)*inMag(kIteration);
    %randn('state',state);
    ngs=ngs.*+tel;          % arriving aberrated wave front
    %state = randn('state');
    zern.\ngs.phase;
    phase = ngs.phase;
    
    inZern(:,kIteration) = zern.c;
    tm.coefs = CL*tm.coefs - (CL*(g - 1) +1)*tmRecon*wfs.slopes;   % this line is before propogation to simulate the delay
%    state(:,1) = tmRecon*wfs.slopes;
%    tm.coefs = - state*[2;-1];   % this line is before propogation to simulate the delay
%    state(:,2) = state(:,1);
    if CL == false
        ngs = ngs*wfs;
    end
    test = randn(100,100);
    ngs=ngs*tm;
    zern.\ngs.phase;
%     imagesc([phase ngs.phase]);
    outZern(:,kIteration) = zern.c;
    % Integrating the DM coefficients
    if CL == true
        ngs = ngs*wfs;
    end
    
    outMag(:,kIteration) = -Utm'*tm.coefs;    
    
%     % Display of turbulence and residual phase
%     figure(1)
%     title(kIteration)
% %     subplot(211)
% %     imagesc([turbPhase,ngs.meanRmPhase]);
% %     subplot(212)
%     imagesc([wm.surface,tm.surface]);
%     drawnow
%     pause
    fprintf('\b\b\b\b\b')
    fprintf('%5d',kIteration)
    ngs_image = fftshift(abs(fft2(ngs.amplitude.*exp(1i*ngs.phase))));
%     figure(1);imagesc(ngs_image);
%     pause
    strehl(kIteration) = max(max(ngs_image))/peakSpot;
    if kIteration > start_science_camera
        longexposure = (ngs_image + (kIteration-start_science_camera-1)*longexposure)/(kIteration-start_science_camera);
    end
    lestrehl(kIteration) = max(max(longexposure))/peakSpot;
end
fprintf('\n')
%figure;plot(strehl);hold on;plot(lestrehl,'r');
tiltStrehl(7+TiltAmplitude) = lestrehl(end);
figure(11);plot(-6:TiltAmplitude,tiltStrehl(1:7+TiltAmplitude))
% drawnow