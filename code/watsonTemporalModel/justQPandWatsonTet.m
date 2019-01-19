clear all;
close all;

stimParams = logspace(.2,2,100); % x3 logarithmically equally
                                 % spaced points between 10^x1 and 10^x2
                                 
                                 

questData = qpInitialize('stimParamsDomainList',{stimParams},...
'psiParamsDomainList',{.001:.001:.012,.5:.5:2,.5:.5:5,.5:.5:3},...
'qpPF',@qpWatsonTemporalModel,...
'nOutcomes',21);

questDataCopy = questData;
%% Adjust these parameters and run the script. 
watsonParams = [.004 2 1 1];

nTrials = 24;
sdNoise = 0.05; % Noise moves around the y-value from watsonTemporalModel.

maxPost = zeros(nTrials,1);
paramGuesses = zeros(nTrials,length(watsonParams));

guessRange = watsonTemporalModel(stimParams,watsonParams);
maxGuess = max(guessRange)+.1;
minGuess = min(guessRange)-.1;

guessBins = minGuess:(maxGuess-minGuess)/20:maxGuess;

%% 
for i = 1:nTrials
    stim(i) = qpQuery(questData);
    
    yGuess(i) = watsonTemporalModel(stim(i),watsonParams) + randn*sdNoise;

    questData = questDataCopy;
    
    for j = 1:i
        b = guessBins - yGuess(j);
        b(b>0) = 0;
        [~,outcome(j)] = max(b);
        questData = qpUpdate(questData,stim(j),outcome(j));
    end
    
    [maxPost(i),maxIndex] = max(questData.posterior);
    paramGuesses(i,:) = questData.psiParamsDomain(maxIndex,:);
    

    guessRange = watsonTemporalModel(stimParams,paramGuesses(i,:));
    maxGuess = max(guessRange)+.1;
    minGuess = min(guessRange)-.1;

    guessBins = minGuess:(maxGuess-minGuess)/20:maxGuess;

end



freqSupport = 0:.01:64;

figure; 
semilogx(watsonTemporalModel(freqSupport,watsonParams),'.k'); hold on;
semilogx(watsonTemporalModel((freqSupport),paramGuesses(end,:)));
%semilogx([questData.trialData.stim],watsonTemporalModel([questData.trialData.stim],watsonParams),'*r')
%semilogx([questData.trialData.stim],yGuess,'*b')


maxPost(end)

figure; 
for i = 1:length(questData.psiParamsDomain)
    if mod(i,100)==0
        semilogx(freqSupport,watsonTemporalModel(freqSupport,questData.psiParamsDomain(i,:)),'.r');
        hold on;
    end
end
