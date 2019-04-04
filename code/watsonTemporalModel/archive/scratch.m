clearvars('-except','questDataCopy');
close all;


% set rng
s = rng;

% Leave the simulatedPsiParams empty to try a random set of params
simulatedPsiParams = [];

% This is a low-pass TTF in noisy fMRI data
%simulatedPsiParams = [10 1 0.83 .8 .1];

% This is a band-pass TTF in noisy fMRI data
%simulatedPsiParams = [1.47 1.75 0.83 1 1];

% Some information about the trials?
nTrials = 256; % how many trials
trialLength = 12; % seconds per trial
baselineTrialRate = 6; % present a gray screen (baseline trial) every X trials


% How talkative is the simulation
showPlots = true;
verbose = true;

%% Set up Q+.

% Get the default Q+ params
myQpParams = qpParams;

% Add the stimulus domain. Log spaced frequencies between 2 and 64 Hz
nStims = 24; 
myQpParams.stimParamsDomainList = {logspace(log10(2),log10(64),nStims)};

% The number of outcome categories.
myQpParams.nOutcomes = 15;

% The headroom is the proportion of outcomes that are reserved above and
% below the min and max output of the Watson model to account for noise
headroom = [0.1 0.3];

% Create an anonymous function from qpWatsonTemporalModel in which we
% specify the number of outcomes for the y-axis response
myQpParams.qpPF = @(f,p) qpWatsonTemporalModel(f,p,myQpParams.nOutcomes,headroom);


% Define the parameter ranges
tau = 0.5:1:10;	% time constant of the center filter (in msecs)
kappa = 0.5:.5:3;	% multiplier of the time-constant for the surround
zeta = 0:0.5:2;	% multiplier of the amplitude of the surround
sigma = 0:0.5:2;	% width of the BOLD fMRI noise against the 0-1 y vals
beta = 0.8:.1:1.1;
myQpParams.psiParamsDomainList = {tau, kappa, zeta, beta, sigma};

% Pick some random params to simulate if none provided (but insist on some
% noise)
if isempty(simulatedPsiParams)
    simulatedPsiParams = [randsample(tau,1) randsample(kappa,1) randsample(zeta,1), randsample(beta,1) 1];
end

% Derive some lower and upper bounds from the parameter ranges. This is
% used later in maximum likelihood fitting
lowerBounds = [tau(1) kappa(1) zeta(1) beta(1) sigma(1)];
upperBounds = [tau(end) kappa(end) zeta(end) beta(end) sigma(end)];

% Create a simulated observer
myQpParams.qpOutcomeF = @(f) qpSimulatedObserver(f,myQpParams.qpPF,simulatedPsiParams);

% Warn the user that we are initializing
if verbose
    tic
    fprintf('Initializing Q+. This may take a minute...\n');
end

% Initialize Q+
% For de-bugging, nice to have a copy

if exist('questDataCopy','var')
    questData = questDataCopy;

else
    questData = qpInitialize(myQpParams);
    questDataCopy = questData;
end



% Warn the user we are about to start
if verbose
    toc
    fprintf('Press space to start.\n');
    pause
    fprintf('Fitting...');
end




%% Construct the model object
temporalFit = tfeIAMP('verbosity','none');


%% Temporal domain of the stimulus
deltaT = 100; % in msecs
totalTime = nTrials*trialLength*1000; % in msecs.
eventDuration = trialLength*1000; % block duration in msecs
initialTrialTime = eventDuration*2;


stimulusStruct.timebase = linspace(0,initialTrialTime-deltaT,initialTrialTime/deltaT);

nTimeSamples = size(stimulusStruct.timebase,2);


eventTimes=[];
for ii=1:(nTrials)
    if mod(ii,baselineTrialRate)~=1
        eventTimes(end+1) = (ii-1)*eventDuration;
    end
end


defaultParamsInfo.nInstances = 1;

stimulusStruct.values(1,:)=zeros(1,nTimeSamples);
stimulusStruct.values(1,(eventTimes(1)/deltaT)+1:eventTimes(1)/deltaT+eventDuration/deltaT)=1;




% randomly initialize freqInstances with a random frequency
freqInstances = randsample(myQpParams.stimParamsDomainList{1},1);
% turn that model frequency into amplitude
modelAmplitudes = watsonTemporalModel(freqInstances, simulatedPsiParams(1:end-2)).*simulatedPsiParams(end-1);


params0 = temporalFit.defaultParams('defaultParamsInfo', defaultParamsInfo);
params0.paramMainMatrix=modelAmplitudes';



%% Define a kernelStruct. In this case, a double gamma HRF
hrfParams.gamma1 = 6;   % positive gamma parameter (roughly, time-to-peak in secs)
hrfParams.gamma2 = 12;  % negative gamma parameter (roughly, time-to-peak in secs)
hrfParams.gammaScale = 10; % scaling factor between the positive and negative gamma componenets

kernelStruct.timebase=linspace(0,15999,16000);

% The timebase is converted to seconds within the function, as the gamma
% parameters are defined in seconds.
hrf = gampdf(kernelStruct.timebase/1000, hrfParams.gamma1, 1) - ...
    gampdf(kernelStruct.timebase/1000, hrfParams.gamma2, 1)/hrfParams.gammaScale;
kernelStruct.values=hrf;

% Normalize the kernel to have unit amplitude
[ kernelStruct ] = normalizeKernelArea( kernelStruct );



%% Create modeled responses

% Set the noise level based on the sd noise from psiParams and report the params
params0.noiseSd = simulatedPsiParams(end);

% Make the noise pink
params0.noiseInverseFrequencyPower = 1;

% First create the response with noise and with convolution
modelResponseStruct = temporalFit.computeResponse(params0,stimulusStruct,[],'AddNoise',true);


%% Initialize the response struct
TR = 1000; % in msecs
responseStruct.timebase = linspace(0,initialTrialTime-TR,initialTrialTime/TR);
responseStruct.values = zeros(1,length(responseStruct.timebase));


%% Construct a packet and model params
thePacket.stimulus = stimulusStruct;
thePacket.response = responseStruct;
thePacket.kernel = kernelStruct;
thePacket.metaData = [];





%% Create a plot in which we can track the model progress
if showPlots
    % Set up the TTF figure
    figure
    subplot(2,1,1)
    freqDomain = logspace(0,log10(100),100);
    a = [];
    semilogx(freqDomain,watsonTemporalModel(freqDomain,simulatedPsiParams(1:end-2).*simulatedPsiParams(end-1)),'-k');
    ylim([-0.5 1.5]);
    xlabel('log stimulus Frequency [Hz]');
    ylabel('Relative response amplitude');
    title('Estimate of Watson TTF');
    hold on
    currentFuncHandle = plot(freqDomain,watsonTemporalModel(freqDomain,simulatedPsiParams(1:end-2)),'-k');

    % Calculate the lower headroom bin offset. We'll use this later
    nLower = round(headroom(1)*myQpParams.nOutcomes);
    nUpper = round(headroom(1)*myQpParams.nOutcomes);
    nMid = myQpParams.nOutcomes - nLower - nUpper;
    
    % Set up the entropy x trial figure
    subplot(2,1,2)
    entropyAfterTrial = nan(1,nTrials);
    currentEntropyHandle = plot(1:nTrials,entropyAfterTrial,'*k');
    xlim([1 nTrials]);
    title('Model entropy by trial number');
    xlabel('Trial number');
    ylabel('Entropy');
end






pctBOLDbins = linspace(-.3,1.3,myQpParams.nOutcomes);

stimNumberReal = 1;

%% Run the simulated experiment.

for ii = 1:nTrials
    
    if mod(ii,baselineTrialRate) == 0
        continue
    else
        
        responseStruct.values = decimate(modelResponseStruct.values,10);

        % Demean the signal and take out any linear trends
        %sampleSignal = detrend(sampleSignal);
        %sampleSignal = detrend(sampleSignal,'constant');
    
    
        thePacket.stimulus = stimulusStruct;
        thePacket.response = responseStruct;
        
         % Model the timeseries using the TFE. 
        params = temporalFit.fitResponse(thePacket,...
            'defaultParamsInfo', defaultParamsInfo, ...
            'searchMethod','linearRegression');
    

    
        responseStruct.timebase(end+1:end+eventDuration/TR) = responseStruct.timebase(end)+TR:TR:responseStruct.timebase(end)+eventDuration;

        params.paramMainMatrix(params.paramMainMatrix < -.3) = -.3;
        params.paramMainMatrix(params.paramMainMatrix > 1.3) = 1.3;

        outcome = discretize(params.paramMainMatrix,pctBOLDbins);
    
    
        questData = qpUpdate(questData,freqInstances(stimNumberReal),outcome(stimNumberReal));
        
        stimNumberReal = stimNumberReal + 1;

        freqInstances(stimNumberReal) = qpQuery(questData);
        modelAmplitudes = watsonTemporalModel(freqInstances, simulatedPsiParams(1:end-2)).*simulatedPsiParams(end-1);
        
        params0.paramMainMatrix=modelAmplitudes';
        params0.matrixRows = stimNumberReal;
        defaultParamsInfo.nInstances = stimNumberReal;
        
        
        stimulusStruct.timebase(end+1:end+eventDuration/deltaT) = linspace(stimulusStruct.timebase(end)+deltaT,stimulusStruct.timebase(end) + eventDuration,eventDuration/deltaT);

        nTimeSamples = size(stimulusStruct.timebase,2);
        
        stimulusStruct.values(:,end+1:end+eventDuration/deltaT) = 0;

        stimulusStruct.values(stimNumberReal,:)=zeros(1,nTimeSamples);
        stimulusStruct.values(stimNumberReal,(eventTimes(stimNumberReal)/deltaT)+1:eventTimes(stimNumberReal)/deltaT+eventDuration/deltaT)=1;
        
        rng(s);
        modelResponseStruct = temporalFit.computeResponse(params0,stimulusStruct,[],'AddNoise',true);
    end
    
    
    % Plot all current stimuli for trials, along with entropy. 
    % These plots will reset each time more data is acquired. 
    if showPlots
        
        % Current guess at the TTF, along with stims and outcomes    
        subplot(2,1,1)
        delete(a);
        a = scatter(freqInstances(1:stimNumberReal-1),params.paramMainMatrix(1:stimNumberReal-1),'o','MarkerFaceColor','b','MarkerEdgeColor','none','MarkerFaceAlpha',.2);          
        psiParamsIndex = qpListMaxArg(questData.posterior);
        psiParamsQuest = questData.psiParamsDomain(psiParamsIndex,:);
        delete(currentFuncHandle)
        currentFuncHandle = plot(freqDomain,watsonTemporalModel(freqDomain,psiParamsQuest(1:end-2)),'-r');

        % Entropy plot
        subplot(2,1,2)
        delete(currentEntropyHandle)
        entropyAfterTrial(1:stimNumberReal-1)=questData.entropyAfterTrial;
        plot(1:stimNumberReal-1,entropyAfterTrial(1:stimNumberReal-1),'*k');
        xlim([1 nTrials]);
        ylim([0 nanmax(entropyAfterTrial)]);
        xlabel('Trial number');
        ylabel('Entropy');

        drawnow
    end
        
end




%% Find out QUEST+'s estimate of the stimulus parameters, obtained
% on the gridded parameter domain.
psiParamsIndex = qpListMaxArg(questData.posterior);
psiParamsQuest = questData.psiParamsDomain(psiParamsIndex,:);
fprintf('Simulated parameters: %0.1f, %0.1f, %0.1f, %0.2f, %0.2f\n', ...
    simulatedPsiParams(1),simulatedPsiParams(2),simulatedPsiParams(3),simulatedPsiParams(4),simulatedPsiParams(5));
fprintf('Max posterior QUEST+ parameters: %0.1f, %0.1f, %0.1f, %0.2f, %0.2f\n', ...
    psiParamsQuest(1),psiParamsQuest(2),psiParamsQuest(3),psiParamsQuest(4),psiParamsQuest(5));

%% Find maximum likelihood fit. Use psiParams from QUEST+ as the starting
% parameter for the search, and impose as parameter bounds the range
% provided to QUEST+.
psiParamsFit = qpFit(questData.trialData,questData.qpPF,psiParamsQuest,questData.nOutcomes,...
    'lowerBounds', lowerBounds,'upperBounds',upperBounds);
fprintf('Maximum likelihood fit parameters: %0.1f, %0.1f, %0.1f, %0.2f, %0.2f\n', ...
    psiParamsFit(1),psiParamsFit(2),psiParamsFit(3),psiParamsFit(4),psiParamsFit(5));



%% Create a figure window for TFE
figure;
hold on
% Add the stimulus profile to the plot
plot(stimulusStruct.timebase/1000,stimulusStruct.values(1,:),'-k','DisplayName','stimulus');

% Now plot the response with convolution and noise, as well as the kernel
%modelResponseStruct = temporalFit.computeResponse(params0,stimulusStruct,kernelStruct,'AddNoise',true);

%temporalFit.plot(modelResponseStruct,'NewWindow',false,'DisplayName','noisy BOLD response');
%plot(kernelStruct.timebase/1000,kernelStruct.values/max(kernelStruct.values),'-b','DisplayName','kernel');

% Plot of the temporal fit results
temporalFit.plot(modelResponseStruct,'Color',[0 1 0],'NewWindow',false,'DisplayName','model fit');
legend('show');legend('boxoff');

plot(sampleSignal,'b','DisplayName','sample signal');
