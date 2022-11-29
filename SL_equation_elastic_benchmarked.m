%
%  Copyright (C) 2016 - 2018 by J. Austermann.
%  This file is part of SLcode.
%  SLcode is free software; you can redistribute it and/or modify
%  it under the terms of the GNU General Public License as published by
%  the Free Software Foundation; either version 2, or (at your option)
%  any later version.
%  SLcode is distributed in the hope that it will be useful,
%  but WITHOUT ANY WARRANTY; without even the implied warranty of
%  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%  GNU General Public License for more details.
%  <http://www.gnu.org/licenses/>.

% Code to solve the elastic sea level equation following 
% Kendall et al., 2005 and Austermann et al., 2015

% J. Austermann 2015

% add paths when run for the first time.
% addpath SLFunctions
% addpath '/Users/jackyaustermann/Documents/MATLAB/m_map'

%% Parameters & Input 
% Specify maximum degree to which spherical transformations should be done
maxdeg = 256;

include_ice_check = 'n'; % choose between y (for yes) and n (for no)


% parameters
rho_ice = 920;
rho_water = 1000;
rho_sed = 2300;
g = 9.80665;


% The following steps help speed up the calculations
% Set up Gauss Legendre grid onto which to interpolate all grids
N = maxdeg; 
[x,w] = GaussQuad(N);
x_GL = acos(x)*180/pi - 90;
lon_GL = linspace(0,360,2*N+1);
lon_GL = lon_GL(1:end-1);

colat = 90 - x_GL;
lon = lon_GL;

[lon_out,lat_out] = meshgrid(lon_GL,x_GL);

% Precompute legendre polynomials
P_lm = cell(N+1,1);
for l=0:N
    P_lm{l+1} = legendre(l,x,'norm');
end


% --------------------------------
% TOPOGRAPHY
% --------------------------------

% load preloaded etopo (including ice) as topo_orig, lon_topo, lat_topo
load topo_SL

% get topography without ice
if N == 64
    topo_bed = topo_bed_64;
elseif N == 128
    topo_bed = topo_bed_128;
elseif N == 256
    topo_bed = topo_bed_256;
elseif N == 512
    topo_bed = topo_bed_512;
elseif N == 1024
    topo_bed = topo_bed_1024;
else
    topo_bed = interp2(lon_topo,lat_topo,topo_bed,lon_out,lat_out);
end

% --------------------------------
% ICE
% --------------------------------

load ice_grid/WAIS

% ice_0_nointerp = ice_Ant;
% ice_j_nointerp = ice_EAIS;


load ice_grid/ice_masks
% 
ice_0_nointerp = Greenland_mask;
ice_j_nointerp = zeros(size(Greenland_mask));

% interpolate ice masks on common grid
ice_0 = interp2(lon_WAIS,lat_WAIS,ice_0_nointerp,lon_out, lat_out);
ice_j = interp2(lon_WAIS,lat_WAIS,ice_j_nointerp,lon_out, lat_out);

del_ice = ice_j - ice_0; 


% --------------------------------
% DYNAMIC TOPOGRAPHY
% --------------------------------

del_DT = zeros(size(del_ice));


% --------------------------------
% SEDIMENT
% --------------------------------

del_sed = zeros(size(del_ice));




%% Set up love number input

% _el stands for elastic love numbers
% _fl stands for fluid love numbers

% prepare love numbers in suitable format and calculate T_lm and E_lm 
% to calculate the fluid case, switch h_el to h_fl, k_el to k_fl and same
% for tidal love numbers
%load SavedLN/prem.l20.ump5.lm10.mat
load SavedLN/prem.l90C.umVM5.lmVM5.mat
h_lm = love_lm(h_el, maxdeg);
k_lm = love_lm(k_el, maxdeg);
h_lm_tide = love_lm(h_el_tide,maxdeg);
k_lm_tide = love_lm(k_el_tide,maxdeg);

E_lm = 1 + k_lm - h_lm;
T_lm = get_tlm(maxdeg);

E_lm_T = 1 + k_lm_tide - h_lm_tide;

%% Solve sea level equation (after Kendall 2005, Dalca 2013 & Austermann et al. 2015)

k_max = 10;   % maximum number of iterations
epsilon = 10^-4; % convergence criterion

% 0 = before
% j = after

% set up present-day topo and ocean function 
topo_0 = topo_bed + ice_0; 
oc_0 = sign_01(topo_0);

% set up topography and ocean function after the ice change
topo_j = topo_0 + del_ice + del_sed + del_DT; % del_ice is negative -> subtract ice that is melted
oc_j = sign_01(topo_j);

% calculate change in sediments and decompose into spherical harmonics
Sed_lm = sphere_har(del_sed,maxdeg,N,P_lm); 

% expand ocean function into spherical harmonics
oc0_lm = sphere_har(oc_0,maxdeg,N,P_lm); 


% initial values for convergence
conv = 'not converged yet';

        
for k = 1:k_max % loop for sea level and topography iteration

    switch conv

        case 'converged!'

        case 'not converged yet'
            
        % expand ocean function into spherical harmonics
        ocj_lm = sphere_har(oc_j,maxdeg,N,P_lm);  
        
        % CHECK ICE MODEL 
        if include_ice_check == 'y'
            % check ice model for floating ice
            check1 = sign_01(-topo_j + ice_j);
            check2 = sign_01(+topo_j - ice_j) .* ...
                (sign_01(-ice_j*rho_ice - (topo_j - ice_j)*rho_water));
         
            ice_j_corr = check1.*ice_j + check2.*ice_j;
        else
            ice_j_corr = ice_j;
        end
        
        del_ice_corrected = ice_j_corr - ice_0; 
        
        deli_lm = sphere_har(del_ice_corrected,maxdeg,N,P_lm);  
        
        
        % calculate topography correction
        TO = topo_0.*(oc_j-oc_0);
        % expand TO function into spherical harmonics
        TO_lm = sphere_har(TO,maxdeg,N,P_lm); 
        
        
        % set up initial guess for sea level change
        if k == 1
            % initial guess of sea level change is just to distribute the
            % ice over the oceans
            delS_lm = ocj_lm/ocj_lm(1)*(-rho_ice/rho_water*deli_lm(1) + ...
                TO_lm(1));
            % convert into spherical harmonics
            % delS_init = inv_sphere_har(delS_lm,maxdeg,N,P_lm);
            
        end
        
        % calculate loading term
        L_lm = rho_ice*deli_lm + rho_water*delS_lm + rho_sed*Sed_lm;

        % calculate contribution from rotation
        La_lm = calc_rot(L_lm,k_el,k_el_tide);
        La_lm = zeros(size(La_lm));

        % calculate sea level perturbation
        % add ice and sea level and multiply with love numbers
        % DT doesn't load!
        delSLcurl_lm_fl = E_lm .* T_lm .* (rho_ice*deli_lm + rho_water*delS_lm + rho_sed*Sed_lm) + ...
            1/g*E_lm_T.*La_lm;

        % convert to spherical harmonics and subtract terms that are part
        % of the topography to get the 'pure' sea level change
        delSLcurl_fl = inv_sphere_har(delSLcurl_lm_fl,maxdeg,N,P_lm);
        delSLcurl = delSLcurl_fl - del_ice_corrected - del_DT - del_sed;


        % compute and decompose RO
        RO = delSLcurl.*oc_j;
        RO_lm = sphere_har(RO,maxdeg,N,P_lm);

        % calculate eustatic sea level perturbation (delta Phi / g)
        delPhi_g = 1/ocj_lm(1) * (- rho_ice/rho_water*deli_lm(1) ...
            - RO_lm(1) + TO_lm(1));

        % calculate overall perturbation of sea level over oceans
        % (spatially varying field and constant offset)
        delSL = delSLcurl + delPhi_g;


        % update topography and ocean function
        topo_j = - delSL + topo_0;
        oc_j = sign_01(topo_j);


        % calculate change in ocean height and decompose
        delS_new = delSL.*oc_j -  topo_0.*(oc_j-oc_0);
        delS_lm_new = sphere_har(delS_new,maxdeg,N,P_lm);


        % calculate convergence criterion chi
        chi = abs( (sum(abs(delS_lm_new)) - sum(abs(delS_lm))) / ...
            sum(abs(delS_lm)) );

        % check convergence against the value epsilon
        % If converged, set the variable conv to 'converged!' so that the
        % calculation exits the loop. If not converged iterate again.
        if chi < epsilon;
            conv = 'converged!';
            disp(['Converged after iteration ' num2str(k) '. Chi was ' num2str(chi) '.'])
        else
            conv = 'not converged yet';
            disp(['Finished iteration ' num2str(k) '. Chi was ' num2str(chi) '.'])
        end

        % update sea sea surface height
        delS_lm = delS_lm_new;
    end

end

% calculate the scaling to normalize the fingerprint (it's normalized to be
% one on average, when averaged over the final ocean basin). 
% calculate change in sea level over final ocean basin
del_scaling =(delSL + del_ice_corrected).*oc_0;
% get the average of that when spreading the water over the whole globe
sca = sphere_har(del_scaling,0,N,P_lm); 
% get the average of that when spreading the water only over the oceans.
scaling_fact = sca(1)/oc0_lm(1);  

%%
% 
% % get bathymetry
% mask0 = sign_01(topo_0);
% temp0 = mask0.*(topo_0);
% A_oc0 = sphere_har(oc_0,0,N,P_lm);
% 
% %for it = 1:length(ice_time_new)
%  
%     % get the ocean area
%    oc_j = sign_01(topo_j);
%    maskj = sign_01(topo_j);
%    tempj = mask.*(topo_j);
%    A_ocj = sphere_har(oc_j,0,N,P_lm);
% 
%     % calculate the change in ocean volume and divide by the ocean area at each time
%     Vol_rsl = sphere_har(tempj-temp0,0,N,P_lm);
%     ESL_rsl = -Vol_rsl/A_ocj;
% %end
% 
% %     Vol_j = sphere_har(tempj,0,N,P_lm);
% %     Vol_0 = sphere_har(temp0,0,N,P_lm);
% %     ESL_rsl = Vol_j/A_ocj - Vol_0/A_oc0;
%     
% 
% % spreading water equally around the present-day ocean area
% ESL = -deli_lm(1)/A_ocj * rho_ice/rho_water; % change A_oc0 to A_ocj for spreading it over the ocean area at time j




%% Plot results

% We only want the sea level change cause by melted ice, so subtract
% del_ice
SL_change_rot = delSL + del_ice_corrected;
% normalize it by the scaling factor
plotSL = SL_change_rot/scaling_fact;

%plotSL = (plotSL - SL_change_rot/scaling_fact)./(SL_change_rot/scaling_fact);
% construct identical colormap to Mitrovica 2009 paper
MyColorMap = [238   44  37
    211 238 244;211 238 244;211 238 244;211 238 244;211 238 244;211 238 244;211 238 244;211 238 244;211 238 244;211 238 244
    173 224 235;173 224 235;173 224 235;173 224 235;173 224 235;173 224 235;173 224 235;173 224 235;173 224 235;173 224 235
    163 201 235
    111 147 201
    96  103 175
    74  102 176
    68  87  165
    58  84  163
    53  69  154
    44  47  137
    38  35  103
    19  15  54
    0   0   0
    0   0   0];

% plot
figure
m_proj('hammer-aitoff','clongitude',0);
m_pcolor([lon_out(:,end/2+1:end)-360 lon_out(:,1:end/2)],lat_out,...
    [plotSL(:,end/2+1:end) plotSL(:,1:end/2)])
m_coast('color',[0 0 0]);
m_grid('box','fancy','xticklabels',[],'yticklabels',[]);
shading flat
colorbar
colormap(MyColorMap/255)
caxis( [-0.05, 1.6] )
title('Sea level fingerprint of West Antarctic Ice Sheet collapse')

