function runStimulusSequence(subject,run,varargin)

% Run the stimulus sequence at the scanner.
%
% Syntax:
%   nextStim = runRealtimeQuestTFE(subject,run,atScanner,varargin)
%
% Description:
%
%
% Inputs:
%   subject                 - String. The name/ID of the subject.
%   run                     - String. The run or acquisition number.


% Optional key/value pairs:
%   checkerboardSize        - Int. size of the tiles of a checkerboard. If = 0,
%                             full screen flash (default - 60). 60 is a
%                             good option for a 1080 x 1920 display
%   allFreqs                - Vector. Frequencies from which to sample, in
%                             hertz.
%   blockDur                - Scalar. Duration of stimulus blocks   (default = 12   [seconds])
%   scanDur                 - Scalar. duration of total run (default = 336 seconds)
%   displayDistance         - Scalar. 106.5; % distance from screen (cm) - (UPenn - SC3T);
%   displayWidth            - Scalar. 69.7347; % width of screen (cm) - (UPenn - SC3T);
%   displayHeight           - Scalar. 39.2257; % height of screen (cm) - (UPenn - SC3T);
%   baselineTrialFrequency  - Int. how frequently a baseline trial occurs
%   tChar                   - String. Letter used for a trigger.
%
%
% Outputs:




%   Written by Andrew S Bock Jul 2016
%   Modified by Steven M Weisberg Jan 2019

% Examples:

%{

1. Sanity Check
subject = 'Ozzy_Test';
run = '0';
checkerboardSize = 0;
allFreqs = 15;
baselineTrialFrequency = 2;
runStimulusSequence(subject,run,'checkerboardSize',checkerboardSize,'allFreqs',allFreqs,'baselineTrialFrequency',baselineTrialFrequency);

1. Q+ Setup
subject = 'Ozzy_Test';
run = '1';
runStimulusSequence(subject,run)
%
%}

%% Parse input
p = inputParser;

% Required input
p.addRequired('subject',@isstr);
p.addRequired('run',@isstr);

% Optional params
p.addParameter('checkerboardSize',60,@isnumeric); % 60 = checker; 0 = screen flash
p.addParameter('allFreqs',[1.875,3.75,7.5,15,30],@isvector);
p.addParameter('blockDur',12,@isnumeric);
p.addParameter('scanDur',360,@isnumeric);
p.addParameter('displayDistance',106.5,@isnumeric);
p.addParameter('displayWidth',69.7347,@isnumeric);
p.addParameter('displayHeight',39.2257,@isnumeric);
p.addParameter('baselineTrialFrequency',6,@isnumeric);
p.addParameter('tChar','t',@isstr);

% Parse
p.parse( subject, run, atScanner, model, varargin{:});

display = struct;
display.distance = p.Results.displayDistance;
display.width = p.Results.displayWidth;
display.height = p.Results.displayHeight;

%% Get Relevant Paths

[subjectPath, scannerPath, ~, ~] = getPaths(subject);



%% TO DO BEFORE WE RUN THIS AGAIN
    %1.  Change the way baseline trials are handled so that we can use 200 as
    %       a "detect baseline".
    %2.  Perhaps also ensure that we present a baseline trial every X trials,
    %       if one has not already been presented by Quest+
    %3.  Change where actualStimuli.txt is stored.
    %4.  Change where nextStimuli[num].txt is stored.
    %5.  Both 3 and 4 could be solved by changing subjectPath to some
    %       scannerPath where scannerPath is a directory on the actual scanner
    %       computer.



%% Debugging?
% This will make the window extra small so you can test while still looking
% at the code.
debug = 0;

if debug
    stimWindow = [10 10 200 200];
else
    stimWindow = [];
end




%% Save input variables
params.stimFreq                 = nan(1,p.Results.scanDur/p.Results.blockDur);
params.trialTypeStrings         = cell(1,length(params.stimFreq));
params.p.Results.allFreqs       = p.Results.allFreqs;
params.checkerboardOrFullscreen = p.Results.checkerboardSize;

%% Set up actualStimuli.txt
% A text file that will serve as a record for all stimuli frequencies
% presented during this run number.
actualStimuliTextFile = strcat('actualStimuli',run,'.txt');
fid = fopen(fullfile(subjectPath,actualStimuliTextFile),'w');
fclose(fid);

%% Initial settings
PsychDefaultSetup(2);
Screen('Preference', 'SkipSyncTests', 2); % Skip sync tests
screens = Screen('Screens'); % get the number of screens
screenid = max(screens); % draw to the external screen

%% For Trigger
a = cd;
if a(1)=='/' % mac or linux
    a = PsychHID('Devices');
    for i = 1:length(a)
        d(i) = strcmp(a(i).usageName, 'Keyboard');
    end
    keybs = find(d);
else % windows
    keybs = [];
end


%% Define black and white
black = BlackIndex(screenid);
white = WhiteIndex(screenid);
grey = white/2;


%% Screen params
res = Screen('Resolution',max(Screen('screens')));
display.resolution = [res.width res.height];
PsychImaging('PrepareConfiguration');
PsychImaging('AddTask', 'General', 'UseRetinaResolution');
[winPtr, windowRect]            = PsychImaging('OpenWindow', screenid, grey, stimWindow);
[mint,~,~] = Screen('GetFlipInterval',winPtr,200);
display.frameRate = 1/mint; % 1/monitor flip interval = framerate (Hz)
display.screenAngle = pix2angle( display, display.resolution );
[center(1), center(2)]          = RectCenter(windowRect); % Get the center coordinate of the window
fix_dot                         = angle2pix(display,0.25); % For fixation cross (0.25 degree)


%% Make images
greyScreen = grey*ones(fliplr(display.resolution));

if p.Results.checkerboardSize == 0
    texture1 = black*ones(fliplr(display.resolution));
    texture2 = white*ones(fliplr(display.resolution));
else
    texture1 = double(checkerboard(p.Results.checkerboardSize/2,res.height/p.Results.checkerboardSize,res.width/p.Results.checkerboardSize)>.5);
    texture2 = double(checkerboard(p.Results.checkerboardSize/2,res.height/p.Results.checkerboardSize,res.width/p.Results.checkerboardSize)<.5);
end

Texture(1) = Screen('MakeTexture', winPtr, texture1);
Texture(2) = Screen('MakeTexture', winPtr, texture2);
Texture(3) = Screen('MakeTexture', winPtr, greyScreen);

%% Display Text, wait for Trigger

commandwindow;
Screen('FillRect',winPtr, grey);
Screen('DrawDots', winPtr, [0;0], fix_dot,black, center, 1);
Screen('Flip',winPtr);
ListenChar(2);
HideCursor;
disp('Ready, waiting for trigger...');

startTime = wait4T(p.Results.tChar);  %wait for 't' from scanner.

%% Drawing Loop
breakIt = 0;
frameCt = 0;

curFrame = 0;
params.startDateTime    = datestr(now);
params.endDateTime      = datestr(now); % this is updated below
elapsedTime = 0;
disp(['Trigger received - ' params.startDateTime]);
blockNum = 0;

% randomly select a stimulus frequency to start with
whichFreq = randi(length(p.Results.allFreqs));
stimFreq = p.Results.allFreqs(whichFreq);

try
    while elapsedTime < p.Results.scanDur && ~breakIt  %loop until 'esc' pressed or time runs out
        thisBlock = ceil(elapsedTime/p.Results.blockDur);


        % If the block time has elapsed, then time to pick a new stimulus
        % frequency.
        if thisBlock > blockNum
            blockNum = thisBlock;

            % Every sixth block, set stimFreq = 0. Will display gray screen
            if mod(blockNum,p.Results.baselineTrialFrequency) == 1
                trialTypeString = 'baseline';
                stimFreq = 0;

            % If it's not the 6th block, then see if Quest+ has a
            % recommendation for which stimulus frequency to present next.
            elseif ~isempty(dir(fullfile(subjectPath,'stimLog','nextStim*')))

                d = dir(fullfile(subjectPath,'stimLog','nextStim*'));
                [~,idx] = max([d.datenum]);
                filename = d(idx).name;
                nextStimNum = sscanf(filename,'nextStimuli%d');
                trialTypeString = ['quest recommendation - ' num2str(nextStimNum)];
                readFid = fopen(fullfile(subjectPath,'stimLog',filename),'r');
                stimFreq = fscanf(readFid,'%d');
                fclose(readFid);

            % If there's no Quest+ recommendation yet, randomly pick a
            % frequency from p.Results.allFreqs.
            else
                trialTypeString = 'random';
                whichFreq = randi(length(p.Results.allFreqs));
                stimFreq = p.Results.allFreqs(whichFreq);
            end

            % Write the stimulus that was presented to a text file so that
            % Quest+ can see what's actually been presented.

            fid = fopen(fullfile(subjectPath,actualStimuliTextFile),'a');
            fprintf(fid,'%d\n',stimFreq);
            fclose(fid);

            % Print the last trial info to the terminal and save it to
            % params.
            disp(['Trial Type - ' trialTypeString]);
            disp(['Trial Number - ' num2str(blockNum) '; Frequency - ' num2str(stimFreq)]);

            params.stimFreq(thisBlock) = stimFreq;
            params.trialTypeStrings{thisBlock} = trialTypeString;

        end


        % We will handle stimFreq = 0 different to just present a gray
        % screen. If it's not zero, we'll flicker.
        % The flicker case:
        if stimFreq ~= 0
            if (elapsedTime - curFrame) > (1/(stimFreq*2))
                frameCt = frameCt + 1;
                Screen( 'DrawTexture', winPtr, Texture( mod(frameCt,2) + 1 )); % current frame
                Screen('Flip', winPtr);
                curFrame = GetSecs - startTime;
            end
        % The gray screen case.
        else
            Screen( 'DrawTexture', winPtr, Texture( 3 )); % gray screen
            Screen('Flip', winPtr);
        end



        % update timers
        elapsedTime = GetSecs-startTime;
        params.endDateTime = datestr(now);
        % check to see if the "esc" button was pressed
        breakIt = escPressed(keybs);
        WaitSecs(0.001);

    end

    % Close screen and save data.
    sca;
    save(fullfile(subjectPath,strcat('stimFreqData_Run',run,'_',datestr(now,'mm_dd_yyyy_HH_MM'))),'params');
    disp(['elapsedTime = ' num2str(elapsedTime)]);
    ListenChar(1);
    ShowCursor;
    Screen('CloseAll');

catch ME
    Screen('CloseAll');
    save(fullfile(subjectPath,strcat('stimFreqData_Run',run)),datestr(now,'mm_dd_yyyy_HH_MM'))),'params');
    ListenChar;
    ShowCursor;
    rethrow(ME);
end
