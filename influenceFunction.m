classdef influenceFunction < handle
    % INFLUENCEFUNCTION Create an influence function object
    %
    % obj = influenceFunction('monotonic',mech) creates a cubic Bezier
    % influence function monotically decreasing from 1 to 0 with the
    % mechanical coupling mech
    %
    % obj = influenceFunction('overshoot',mech) creates a cubic Bezier
    % influence function with a negative overshoot and the mechanical
    % coupling mech
    %
    % Try show(obj) to view a cut of the influence function
    
    properties
        % mechanicalCoupling
        mechCoupling;
        % spline polynomials coefs
        splineP;
        % path listener
        bezierListener;
        % modes
        modes
        % influence function tag
        tag = 'BEZIER INFLUENCE FUN';
    end
    
    properties (SetObservable=true)
        % path
        bezier;
    end
    
    properties (Dependent)
        % points
        P;
    end
    
    properties (Access=private)
        % points
        p_P;
        % influence function display handle;
        displayHandle
        p_xScale;
        log
    end
    
    methods
        
        %% Constructor
        function obj = influenceFunction(points,mech)
            obj.p_P = zeros(7,2);
            obj.p_P(1,:) = [0,1];
            obj.p_P(2,2) = 1;
            obj.p_P(6,2) = 0;
            obj.p_P(7,:) = [2,0];
            if ischar(points)
                switch points
                    case 'overshoot'
                        points = {0.2,[0.4,0.7],[0.5,0.4],0.3,1};
                    case 'monotonic'
                        points = {0.2,[0.4,0.7],[0.6,0.4],1,1};
                end
            end
            obj.mechCoupling = mech;
            obj.P = points;
            obj.bezierListener = addlistener(obj,'bezier','PostSet',...
                @(src,evnt) obj.show );
            obj.bezierListener.Enabled = false;
            obj.log = logBook.checkIn(obj);
        end
        
        %% Destructor
        function delete(obj)
            if ishandle(obj.displayHandle)
                delete(get(obj.displayHandle,'parent'));
            end
            checkOut(obj.log,obj)
        end
        
        function display(obj)
            %% DISP Display object information
            %
            % disp(obj) prints information about the influenceFunction
            % object
            fprintf('___ %s ___\n',obj.tag)
            fprintf('  . mechanical coupling: %3.1f\n',...
                obj.mechCoupling);            
            fprintf('----------------------------------------------------\n')
        end
                
        %% Set and Get P properties
        function out = get.P(obj)
            out = obj.p_P;
        end
        function set.P(obj,val)
            obj.p_P(2,1) = val{1};
            obj.p_P(3,:) = val{2};
            obj.p_P(4,:) = val{3};
            obj.p_P(5,:) = (-1/val{4})*obj.p_P(3,:)+(1+1/val{4})*obj.p_P(4,:);
            obj.p_P(6,1) = val{5};
            t = linspace(0,1,101)';
            obj.bezier = ...
                ((1-t).^3)*obj.p_P(1,:) + ...
                3.*((1-t).^2.*t)*obj.p_P(2,:) + ...
                3.*((1-t).*t.^2)*obj.p_P(3,:) + ...
                (t.^3)*obj.p_P(4,:);
            t(1) = [];
            obj.bezier = [obj.bezier ; ...
                ((1-t).^3)*obj.p_P(4,:) + ...
                3.*((1-t).^2.*t)*obj.p_P(5,:) + ...
                3.*((1-t).*t.^2)*obj.p_P(6,:) + ...
                (t.^3)*obj.p_P(7,:) ];
            obj.p_xScale = spline(obj.bezier(:,2),obj.bezier(:,1),obj.mechCoupling);
            obj.bezier(:,1) = obj.bezier(:,1)/obj.p_xScale;
            u = [-flipud(obj.bezier(:,1)) ; obj.bezier(2:end,1)];
            v = [flipud(obj.bezier(:,2)) ; obj.bezier(2:end,2)];
            obj.splineP = spline(u,v);
            
        end
        
        function out = mtimes(obj,c)
            %% MTIMES Influence function multiplication
            %
            % v = obj*c multiply the influence functions in obj by the
            % vector c
            
            out = obj.modes*c;
        end
        function out = mldivide(obj,c)
            %% MLDIVIDE Influence function projection
            %
            % v = obj\c project the influence functions onto the vector c
            
            out = obj.modes\c;
        end
        
        function show(obj)
            P = obj.p_P;
            P(:,1) = P(:,1)/obj.p_xScale;
            if ishandle(obj.displayHandle)
                x = linspace(0,obj.bezier(end,1),101);
                set(obj.displayHandle(1),...
                    'XData',obj.bezier(:,1),...
                    'YData',obj.bezier(:,2))
                set(obj.displayHandle(2),...
                    'YData',ppval(obj.splineP,x))
                for kP=1:7
                    set(obj.displayHandle(2+kP),...
                        'Xdata',P(kP,1),'Ydata',P(kP,2))
                end
            else
                x = linspace(0,obj.bezier(end,1),101);
                obj.displayHandle = plot(obj.bezier(:,1),obj.bezier(:,2),x,ppval(obj.splineP,x),'r--');
                kPoints = [1 4 7];
%                 kHandles = [2 3 5 6];
                for kP=1:7
                    if any(kP==kPoints)
                        obj.displayHandle(2+kP) = ...
                            line(P(kP,1),P(kP,2),...
                            'LineStyle','None',...
                            'Marker','o',...
                            'MarkerFaceColor','r',...
                            'MarkerEdgeColor','k');%,...
%                             'ButtonDownFcn',@button_down,...
%                             'UserData',kP);
                    else
                        obj.displayHandle(2+kP) = ...
                            line(P(kP,1),P(kP,2),...
                            'LineStyle','None',...
                            'Marker','d',...
                            'MarkerFaceColor','k',...
                            'MarkerEdgeColor','r');%,...
%                             'ButtonDownFcn',@button_down,...
%                             'UserData',kP);
                    end
                end
                grid
                xlabel('Normalized actuator pitch')
                ylabel('Normalized stroke')
            end
            % TO FIX: moving the points is messy if the abscisses of the
            % Bezier curves is normalized wrt to mechanical coupling value
            function button_down(src,evnt)
                % src - the object that is the source of the event
                % evnt - empty for this property
                sel_typ = get(gcbf,'SelectionType');
                set(gcbf,'WindowButtonMotionFcn',@wbmcb)
                ah = findobj(gcbf,'type','axes');
                switch sel_typ
                    case 'normal'
%                         disp('User clicked left-mouse button')
                        set(src,'Selected','on')
                    case 'extend'
%                         disp('User did a shift-click')
                        set(src,'Selected','on')
                    case 'alt'
                        disp('User did a control-click')
%                         set(gco,'Selected','off')
                        set(gcbf,'WindowButtonMotionFcn','')
                        %                         set(src,'SelectionHighlight','off')
                end
                function wbmcb(src,evnt)
%                                 obj.p_P(2,1) = val{1};
%             obj.p_P(3,:) = val{2};
%             obj.p_P(4,:) = val{3};
%             obj.p_P(5,:) = (-1/val{4})*obj.p_P(3,:)+(1+1/val{4})*obj.p_P(4,:);
%             obj.p_P(6,1) = val{5};
                    cp = get(ah,'CurrentPoint');%*obj.p_xScale
                    iP = get(gco,'UserData');
                    if iP==2
                        obj.P = {cp(1,1),...
                            obj.p_P(3,:),...
                            obj.p_P(4,:),...
                            norm(obj.p_P(3,:)-obj.p_P(4,:))/norm(obj.p_P(5,:)-obj.p_P(4,:)),...
                            obj.p_P(6,1)};
                    elseif iP==3
                        P3 = [cp(1,1),cp(1,2)];
                        obj.P = {obj.p_P(2,1),...
                            P3,...
                            obj.p_P(4,:),...
                            norm(P3-obj.p_P(4,:))/norm(obj.p_P(5,:)-obj.p_P(4,:)),...
                            obj.p_P(6,1)};
                    elseif iP==4
                        P4 = [cp(1,1),cp(1,2)];
                        obj.P = {obj.p_P(2,1),...
                            obj.p_P(3,:),...
                            P4,...
                            norm(obj.p_P(3,:)-P4)/norm(obj.p_P(5,:)-P4),...
                            obj.p_P(6,1)};
                    elseif iP==5
                        P5 = [cp(1,1),cp(1,2)];
                        obj.P = {obj.p_P(2,1),...
                            obj.p_P(3,:),...
                            obj.p_P(4,:),...
                            norm(obj.p_P(3,:)-obj.p_P(4,:))/norm(P5-obj.p_P(4,:)),...
                            obj.p_P(6,1)};
                    elseif iP==6
                        obj.P = {obj.p_P(2,1),...
                            obj.p_P(3,:),...
                            obj.p_P(4,:),...
                            norm(obj.p_P(3,:)-obj.p_P(4,:))/norm(obj.p_P(5,:)-obj.p_P(4,:)),...
                            cp(1,1)};
                    end
                    show(obj), drawnow
                end
            end
        end
        
        function setInfluenceFunction(obj,nIF,resolution,validActuator,ratioTelDm,offset)
%             if nargin<5
%                 ratioTelDm = 1;
%             end
%             z = linspace(-1,1,nIF)*(nIF-1)/2;
            xIF = linspace(-1,1,nIF)*(nIF-1)/2 - offset(1);
            yIF = linspace(-1,1,nIF)*(nIF-1)/2 - offset(2);
            u0 = ratioTelDm.*linspace(-1,1,resolution)*(nIF-1)/2;
%             w = zeros(resolution,nIF);
%             w = spalloc(resolution,nIF,nIF*resolution);
%             fprintf('::::::::::\n @(influenceFunction)> Spline interpolation of the bezier curves... (%4d:     ',nIF)
%             for kIF = 1:nIF
%                 u = u0 - z(kIF);
%                 index = u >= -obj.bezier(end,1) & u <= obj.bezier(end,1);
%                 w(index,kIF) = ppval(obj.splineP,u(index));
%                 fprintf('\b\b\b\b%4d',kIF)
%             end
%             fprintf(')\n')
%             obj.modes = zeros(resolution^2,sum(validActuator(:)));
            nValid = sum(validActuator(:));
            obj.modes = spalloc(resolution^2,nValid,resolution^2*nValid);
            kIF = 0;
            fprintf(' @(influenceFunction)> Computing the 2D DM zonal modes... (%4d:     ',nValid)
            for jIF = 1:nIF
                u = u0 - xIF(jIF);
                wu = zeros(resolution,1);
                index = u >= -obj.bezier(end,1) & u <= obj.bezier(end,1);
                wu(index) = ppval(obj.splineP,u(index));
                for iIF = 1:nIF
                    v = u0 - yIF(iIF);
                    wv = zeros(resolution,1);
                    index = v >= -obj.bezier(end,1) & v <= obj.bezier(end,1);
                    wv(index) = ppval(obj.splineP,v(index));
                    if validActuator(iIF,jIF)
                        buffer = sparse(wv*wu');
                        kIF = kIF + 1;
                        obj.modes(:,kIF) = buffer(:);
                        fprintf('\b\b\b\b%4d',kIF)
                    end
                end
            end
            fprintf(')\n::::::::::\n')
        end
    end
    
end