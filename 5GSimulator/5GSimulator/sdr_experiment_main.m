function experimentSummary = sdr_experiment_main(mode, configName, varargin)
%SDR_EXPERIMENT_MAIN End-to-end orchestration for the SDR + USRP experiment.
%   The workflow covers:
%     1) 软件信道（含时延扩展 + 多普勒）下的链路验证；
%     2) 在发送端插入同步头（ZC）并导出 USRP 发送基带；
%     3) 将接收端（软件/USRP 回放）对齐后做性能与吞吐汇总。
%
%   Usage examples:
%     % 仅软件信道 + 性能统计（默认基线 10 Mbps 配置）
%     summary = sdr_experiment_main();
%
%     % 生成 USRP 发送基带文件，不做接收处理
%     sdr_experiment_main('tx-only', 'baseline10Mbps', 'OutputDir', 'results');
%
%     % 加载 USRP 捕获文件，进行同步与解调
%     sdr_experiment_main('rx-process', 'baseline10Mbps', 'CaptureFile', 'capture.mat');
%
%   The configs encode both the 10 Mbps target and a “max throughput” sweep.
%
%   Parameters (Name-Value):
%     'OutputDir'   : folder to store tx/rx artifacts (default: 'results')
%     'CaptureFile' : MAT file that stores variable 'rxCapture' or 'rx_signal'
%     'SaveWaveform': logical, whether to save tx waveform (default: true)
%
%   The function returns a struct with parameter snapshots and KPIs.

arguments
    mode (1,1) string = "software"
    configName (1,1) string = "baseline10Mbps"
end
arguments (Repeating)
    varargin
end

mode = lower(string(mode));
mode = validatestring(mode, ["software","tx-only","rx-process"]);
configName = string(configName);

opts = parseExperimentOptions(varargin{:});
configs = buildExperimentConfigs();

if ~isfield(configs, configName)
    error('Unknown config "%s". Available configs: %s', configName, strjoin(fieldnames(configs), ', '));
end

config = configs.(configName);
rng(config.randomSeed);
syncCfg = defaultSyncSettings();

% Ensure scenario name is char for older MATLAB versions
simParams = Parameters.SimulationParameters(char(config.baseScenario));
simParams = applyExperimentConfig(simParams, config);

switch mode
    case "software"
        runMode = struct('skipChannel', false, 'skipRxProcessing', false, 'useCapture', false);
    case "tx-only"
        runMode = struct('skipChannel', true, 'skipRxProcessing', true, 'useCapture', false);
    case "rx-process"
        if isempty(opts.captureFile)
            error('rx-process mode requires ''CaptureFile'' to be provided.');
        end
        runMode = struct('skipChannel', true, 'skipRxProcessing', false, 'useCapture', true);
end

experimentSummary = runSoftwareChannelExperiment(simParams, config, syncCfg, runMode, opts);
experimentSummary.sweepResults = {};

% Sweep multiple configs if requested (executes sequentially)
if ~isempty(opts.sweepConfigs)
    sweepList = cellstr(opts.sweepConfigs);
    sweepResults = cell(numel(sweepList),1);
    for iCfg = 1:numel(sweepList)
        cfgName = sweepList{iCfg};
        if ~isfield(configs, cfgName)
            warning('Sweep config "%s" not found, skipping.', cfgName);
            continue;
        end
        cfg = configs.(cfgName);
        rng(cfg.randomSeed);
        syncCfgLocal = defaultSyncSettings();
        simParamsLocal = Parameters.SimulationParameters(char(cfg.baseScenario));
        simParamsLocal = applyExperimentConfig(simParamsLocal, cfg);
        sweepResults{iCfg} = runSoftwareChannelExperiment(simParamsLocal, cfg, syncCfgLocal, runMode, opts);
    end
    experimentSummary.sweepResults = sweepResults;
    reportSweep(sweepResults, opts);
end
end

%% ------------------------------------------------------------------------
function opts = parseExperimentOptions(varargin)
parser = inputParser;
parser.addParameter('OutputDir', 'results', @(x) ischar(x) || isstring(x));
parser.addParameter('CaptureFile', '', @(x) ischar(x) || isstring(x));
parser.addParameter('SaveWaveform', true, @islogical);
parser.addParameter('EnablePlots', true, @islogical);
parser.addParameter('SweepConfigs', {"baseline10Mbps","peakThroughput","wide256QAM"}, @(x) iscell(x) || isstring(x));
parser.addParameter('SnrDb', 20, @(x) isempty(x) || isscalar(x));
parser.parse(varargin{:});

opts.outputDir = char(parser.Results.OutputDir);
opts.captureFile = char(parser.Results.CaptureFile);
opts.saveWaveform = parser.Results.SaveWaveform;
opts.enablePlots = parser.Results.EnablePlots;
opts.sweepConfigs = parser.Results.SweepConfigs;
opts.snrDb = parser.Results.SnrDb;
end

%% ------------------------------------------------------------------------
function configs = buildExperimentConfigs()
% Baseline: 10 MHz, 16QAM r~0.6, target >=10 Mbps
configs.baseline10Mbps = struct( ...
    'name',              "baseline10Mbps", ...
    'description',       "10 MHz @ 30 kHz SCS, 16QAM r≈0.6, diamond pilots 1/6×1/4", ...
    'baseScenario',      "LTEAcompliant", ...
    'randomSeed',        42, ...
    'nFrames',           10, ...
    'numerology',        struct('subcarrierSpacing', 30e3, ...      % 30 kHz
                                'nSubcarriers',     600, ...        % ~10 MHz payload
                                'nSymbols',         14, ...
                                'cpFraction',       1/8, ...
                                'samplingRate',     30.72e6, ...
                                'frameDuration',    1e-3), ...
    'rf',                struct('centerFrequency', 2.6e9, ...
                                'txPowerdBm',      30), ...
    'channel',           struct('pdp',           "ExtendedVehicularA", ...
                                'dopplerModel',  "Jakes", ...
                                'userSpeed',     33.3, ...          % 120 km/h
                                'noisePower',    14), ...
    'mcs',               9, ...                                    % 16QAM, coding rate ≈0.6
    'waveform',          "OFDM", ...
    'pilot',             struct('pattern', "Diamond", 'freqSpacing', 6, 'timeSpacing', 4), ...
    'targets',           struct('throughputMbps', 10, 'note', "Hit >=10 Mbps with robust pilots") ...
    );

% Peak throughput exploration: 20 MHz, 64QAM r≈0.87
configs.peakThroughput = struct( ...
    'name',              "peakThroughput", ...
    'description',       "20 MHz @ 30 kHz SCS, 64QAM r≈0.87, sparser pilots 1/8×1/6", ...
    'baseScenario',      "LTEAcompliant", ...
    'randomSeed',        99, ...
    'nFrames',           10, ...
    'numerology',        struct('subcarrierSpacing', 30e3, ...
                                'nSubcarriers',     1200, ...       % ~20 MHz payload
                                'nSymbols',         14, ...
                                'cpFraction',       1/8, ...
                                'samplingRate',     61.44e6, ...
                                'frameDuration',    1e-3), ...
    'rf',                struct('centerFrequency', 3.5e9, ...
                                'txPowerdBm',      30), ...
    'channel',           struct('pdp',           "ExtendedVehicularA", ...
                                'dopplerModel',  "Jakes", ...
                                'userSpeed',     27.8, ...          % 100 km/h
                                'noisePower',    12), ...
    'mcs',               14, ...                                   % 64QAM high rate
    'waveform',          "OFDM", ...
    'pilot',             struct('pattern', "Diamond", 'freqSpacing', 8, 'timeSpacing', 6), ...
    'targets',           struct('throughputMbps', 20, 'note', "Search peak throughput with denser bandwidth") ...
    );

% Wide-band, high-order modulation for sweep comparison
configs.wide256QAM = struct( ...
    'name',              "wide256QAM", ...
    'description',       "30 MHz @ 60 kHz SCS, 256QAM r≈0.75, pilots 1/8×1/6", ...
    'baseScenario',      "LTEAcompliant", ...
    'randomSeed',        123, ...
    'nFrames',           10, ...
    'numerology',        struct('subcarrierSpacing', 60e3, ...
                                'nSubcarriers',     1024, ...
                                'nSymbols',         14, ...
                                'cpFraction',       1/8, ...
                                'samplingRate',     122.88e6, ...
                                'frameDuration',    1e-3), ...
    'rf',                struct('centerFrequency', 3.5e9, ...
                                'txPowerdBm',      30), ...
    'channel',           struct('pdp',           "ExtendedVehicularA", ...
                                'dopplerModel',  "Jakes", ...
                                'userSpeed',     27.8, ...
                                'noisePower',    12), ...
    'mcs',               13, ... % 256QAM high rate
    'waveform',          "OFDM", ...
    'pilot',             struct('pattern', "Diamond", 'freqSpacing', 8, 'timeSpacing', 6), ...
    'targets',           struct('throughputMbps', 40, 'note', "High-order modulation sweep point") ...
    );
end

%% ------------------------------------------------------------------------
function syncCfg = defaultSyncSettings()
syncCfg.length = 255;
syncCfg.root = 23; % choose a root that is coprime with the length to satisfy ZC constraints
syncCfg.boostdB = 6;
syncCfg.guardSamples = 256;
syncCfg.sequence = zadoffChuSeq(syncCfg.root, syncCfg.length);
syncCfg.sequence = db2mag(syncCfg.boostdB) .* syncCfg.sequence;
end

%% ------------------------------------------------------------------------
function simParams = applyExperimentConfig(simParams, config)
simParams.simulation.centerFrequency    = config.rf.centerFrequency;
simParams.simulation.txPowerBaseStation = config.rf.txPowerdBm;
simParams.simulation.txPowerUser        = config.rf.txPowerdBm;
simParams.simulation.userVelocity       = config.channel.userSpeed;
simParams.simulation.nFrames            = config.nFrames;

simParams.modulation.waveform           = {char(config.waveform)};
simParams.modulation.numerOfSubcarriers = config.numerology.nSubcarriers;
simParams.modulation.subcarrierSpacing  = config.numerology.subcarrierSpacing;
simParams.modulation.nSymbolsTotal      = config.numerology.nSymbols;
% Use a single CP symbol to stay compatible with built-in guard checks
simParams.modulation.nGuardSymbols      = 1;
simParams.modulation.samplingRate       = config.numerology.samplingRate;
simParams.modulation.mcs                = config.mcs;

simParams.channel.powerDelayProfile     = char(config.channel.pdp);
simParams.channel.dopplerModel          = char(config.channel.dopplerModel);
simParams.simulation.channelEstimationMethod = 'PilotAided';
simParams.simulation.pilotPattern            = char(config.pilot.pattern);

simParams.simulation.sweepValue         = simParams.simulation.pathloss;
simParams.phy.noisePower                = config.channel.noisePower;

% Align schedule with the configured number of subcarriers (prevent mismatch)
if isfield(simParams.schedule, 'fixedScheduleDL')
    simParams.schedule.fixedScheduleDL{1} = sprintf('UE1:%d', simParams.modulation.numerOfSubcarriers);
end

% refresh dependent parameters after manual tweaks
simParams.checkParameters();
simParams.dependentParameters();
end

%% ------------------------------------------------------------------------
function experimentSummary = runSoftwareChannelExperiment(simParams, config, syncCfg, runMode, opts)
[Links, BS, UE] = Topology.getTopology(simParams);
Links = simParams.initializeLinks(Links, BS, UE);

logParameterSummary(config, simParams, syncCfg);

nBS      = length(BS);
nUE      = length(UE);
dimLinks = length(Links);
nFrames  = simParams.simulation.nFrames;

perSweepResults = cell(dimLinks, dimLinks, nFrames);
txFrames = cell(nFrames, 1);
rxFrames = cell(nFrames, 1);

captureData = [];
if runMode.useCapture
    captureData = loadCapturedWaveform(opts.captureFile);
    captureCursor = 1;
end

for iFrame = 1:nFrames
    % update / new channel realization
    for iBS = 1:nBS
        for iLink = 1:length(Links)
            if simParams.simulation.simulateDownlink && ~isempty(Links{BS{iBS}.ID, iLink}) ...
                    && strcmp(Links{BS{iBS}.ID, iLink}.Type, 'Primary')
                Links{BS{iBS}.ID, iLink}.updateLink(simParams, Links, iFrame);
            elseif simParams.simulation.simulateDownlink && ~isempty(Links{BS{iBS}.ID, iLink}) ...
                    && strcmp(Links{BS{iBS}.ID, iLink}.Type, 'Interference')
                Links{BS{iBS}.ID, iLink}.Channel.NewRealization(iFrame);
            end
        end
    end

    if simParams.simulation.simulateDownlink
        for iBS = 1:nBS
            BS{iBS}.generateTransmitSignal(Links);
        end

        for iUE = 1:nUE
            UEID = UE{iUE}.ID;
            primaryLink = Links{UE{iUE}.TransmitBS(1), UEID};
            if ~primaryLink.isScheduled
                continue;
            end

            payloadTx = primaryLink.TransmitSignal;          % original waveform length expected by channel
            txWithSync = prependSync(payloadTx, syncCfg);    % exported waveform (tx-only / capture)
            txFrames{iFrame} = txWithSync;

            if runMode.skipChannel && ~runMode.useCapture
                % For tx-only export path we stop after waveform build
                continue;
            end

            if runMode.useCapture
                [rxCurrent, captureCursor] = sliceCaptureFrame(captureData, syncCfg, primaryLink.Modulator.WaveformObject.Nr.SamplesTotal, captureCursor);
                rxFrames{iFrame} = rxCurrent;
                if runMode.skipRxProcessing
                    continue;
                end
                dataOnly = extractFrame(applyExtraNoise(rxCurrent, opts.snrDb), syncCfg, primaryLink.Modulator.WaveformObject.Nr.SamplesTotal);
                Links{UE{iUE}.TransmitBS(1), UEID}.TransmitSignal = payloadTx(end-length(dataOnly)+1:end, :); %#ok<NASGU>
                Links{UE{iUE}.TransmitBS(1), UEID}.ReceiveSignal = dataOnly;
                UE{iUE}.processReceiveSignal(dataOnly, Links, simParams);
            else
                % Pure software channel: do not inject sync into the waveform; use native path
                primaryLink.TransmitSignal = payloadTx;
                primaryLink.generateReceiveSignal();
                rxCurrent = applyExtraNoise(primaryLink.ReceiveSignal, opts.snrDb);
                rxFrames{iFrame} = rxCurrent;
                if runMode.skipRxProcessing
                    continue;
                end
                Links{UE{iUE}.TransmitBS(1), UEID}.TransmitSignal = payloadTx; %#ok<NASGU>
                Links{UE{iUE}.TransmitBS(1), UEID}.ReceiveSignal = rxCurrent;
                UE{iUE}.processReceiveSignal(rxCurrent, Links, simParams);
            end
            primaryLink.calculateSNR(simParams.constants.BOLTZMANN, simParams.phy.temperature);
            perSweepResults{UE{iUE}.TransmitBS(1), UEID, iFrame} = primaryLink.getResults(simParams.simulation.saveData);
        end
    end
end

simResults = {perSweepResults};
if isfield(simParams.simulation, 'averageFrameDuration')
    avgDuration = simParams.simulation.averageFrameDuration;
else
    avgDuration = [];
end
if isempty(avgDuration)
    avgDuration = config.numerology.frameDuration;
end

if simParams.simulation.simulateDownlink
    if runMode.skipRxProcessing
        dlResults = [];
    else
        dlResults = Results.SimulationResults(nFrames, 1, nBS, nUE, avgDuration, 'downlink');
        dlResults.collectResults(simResults, UE);
        dlResults.postProcessResults();
    end
else
    dlResults = [];
end

if opts.saveWaveform
    ensureFolder(opts.outputDir);
    save(fullfile(opts.outputDir, sprintf('tx_waveform_%s.mat', config.name)), ...
        'txFrames', 'config', 'syncCfg', 'simParams', '-v7.3');
    if ~runMode.skipChannel && ~runMode.skipRxProcessing
        save(fullfile(opts.outputDir, sprintf('rx_waveform_%s.mat', config.name)), ...
            'rxFrames', 'config', 'syncCfg', 'simParams', '-v7.3');
    end
end

experimentSummary = struct();
experimentSummary.config = config;
experimentSummary.sync = syncCfg;
experimentSummary.parameters = snapshotParameters(simParams);
experimentSummary.txFrames = txFrames;
experimentSummary.rxFrames = rxFrames;
experimentSummary.downlinkResults = dlResults;
experimentSummary.mode = runMode;
experimentSummary.kpi = collectKpi(dlResults);

reportResults(experimentSummary, opts);
end

%% ------------------------------------------------------------------------
function logParameterSummary(config, simParams, syncCfg)
fprintf('[%s] 关键参数:\n', config.name);
fprintf('  场景: %s | 波形: %s | MCS: %d\n', config.baseScenario, config.waveform, config.mcs);
fprintf('  载频: %.2f GHz | 采样率: %.2f Msps | 带宽(近似): %.2f MHz\n', ...
    simParams.simulation.centerFrequency/1e9, simParams.modulation.samplingRate/1e6, ...
    (simParams.modulation.numerOfSubcarriers * simParams.modulation.subcarrierSpacing)/1e6);
fprintf('  子载波间隔: %.0f kHz | 子载波数: %d | 每帧符号: %d | CP符号: %d\n', ...
    simParams.modulation.subcarrierSpacing/1e3, simParams.modulation.numerOfSubcarriers, ...
    simParams.modulation.nSymbolsTotal, simParams.modulation.nGuardSymbols);
fprintf('  信道: %s | 多普勒: %s | UE速率: %.1f km/h | 噪声功率: %.1f dB\n', ...
    simParams.channel.powerDelayProfile, simParams.channel.dopplerModel, ...
    simParams.simulation.userVelocity*3.6, simParams.phy.noisePower);
fprintf('  导频: %s (freq 1/%d, time 1/%d) | 同步头: ZC len=%d, boost=%ddB, guard=%d\n', ...
    config.pilot.pattern, config.pilot.freqSpacing, config.pilot.timeSpacing, ...
    syncCfg.length, syncCfg.boostdB, syncCfg.guardSamples);
fprintf('  目标吞吐: >= %.1f Mbps | 备注: %s\n\n', ...
    config.targets.throughputMbps, config.targets.note);
end

%% ------------------------------------------------------------------------
function out = prependSync(payload, syncCfg)
guard = zeros(syncCfg.guardSamples, size(payload, 2));
out = [guard; syncCfg.sequence; payload];
end

%% ------------------------------------------------------------------------
function dataOnly = extractFrame(rxSignal, syncCfg, expectedSamples)
[corrVal, lags] = xcorr(rxSignal(:, 1), syncCfg.sequence);
[~, peakIdx] = max(abs(corrVal));
startSample = lags(peakIdx) + length(syncCfg.sequence) + syncCfg.guardSamples + 1;
startSample = max(startSample, 1);
stopSample = min(startSample + expectedSamples - 1, size(rxSignal, 1));
dataOnly = rxSignal(startSample:stopSample, :);
end

%% ------------------------------------------------------------------------
function captureData = loadCapturedWaveform(captureFile)
raw = load(captureFile);
if isfield(raw, 'rxCapture')
    captureData = raw.rxCapture;
elseif isfield(raw, 'rx_signal')
    captureData = raw.rx_signal;
elseif isfield(raw, 'rxSignal')
    captureData = raw.rxSignal;
else
    error('Capture file must contain variable rxCapture / rx_signal / rxSignal.');
end
end

%% ------------------------------------------------------------------------
function [frame, nextCursor] = sliceCaptureFrame(captureData, syncCfg, expectedSamples, startCursor)
dataSlice = captureData(startCursor:end, :);
[corrVal, lags] = xcorr(dataSlice(:, 1), syncCfg.sequence);
[~, peakIdx] = max(abs(corrVal));
startSample = lags(peakIdx) + length(syncCfg.sequence) + syncCfg.guardSamples + 1;
startSample = max(startSample, 1);
stopSample = min(startSample + expectedSamples - 1, size(dataSlice, 1));
frame = dataSlice(startSample:stopSample, :);
nextCursor = startCursor + stopSample;
end

%% ------------------------------------------------------------------------
function noisy = applyExtraNoise(signalIn, snrDb)
if isempty(snrDb)
    noisy = signalIn;
    return;
end
sigPow = mean(abs(signalIn).^2,'all');
noisePow = sigPow / (10^(snrDb/10));
noise = sqrt(noisePow/2) * (randn(size(signalIn)) + 1j*randn(size(signalIn)));
noisy = signalIn + noise;
end

%% ------------------------------------------------------------------------
function ensureFolder(folderPath)
if ~exist(folderPath, 'dir')
    mkdir(folderPath);
end
end

%% ------------------------------------------------------------------------
function paramSnap = snapshotParameters(simParams)
paramSnap = struct();
paramSnap.centerFrequency = simParams.simulation.centerFrequency;
paramSnap.bandwidthHz = simParams.modulation.numerOfSubcarriers * simParams.modulation.subcarrierSpacing;
paramSnap.samplingRate = simParams.modulation.samplingRate;
paramSnap.subcarrierSpacing = simParams.modulation.subcarrierSpacing;
paramSnap.nSubcarriers = simParams.modulation.numerOfSubcarriers;
paramSnap.nSymbols = simParams.modulation.nSymbolsTotal;
paramSnap.cpSymbols = simParams.modulation.nGuardSymbols;
paramSnap.waveform = simParams.modulation.waveform;
paramSnap.mcsIndex = simParams.modulation.mcs;
paramSnap.channel = simParams.channel;
paramSnap.txPowerBaseStation = simParams.simulation.txPowerBaseStation;
paramSnap.pilotPattern = simParams.simulation.pilotPattern;
end

%% ------------------------------------------------------------------------
function kpi = collectKpi(dlResults)
if isempty(dlResults)
    kpi = struct('throughput', [], 'ber', [], 'fer', []);
    return;
end
throughput = dlResults.userResults.throughput.values;
ber = dlResults.userResults.BERCoded.values;
fer = dlResults.userResults.FER.values;

kpi = struct();
kpi.meanThroughput = mean(throughput);
kpi.peakThroughput = max(throughput);
kpi.meanBer = mean(ber);
kpi.meanFer = mean(fer);
end

%% ------------------------------------------------------------------------
function reportResults(summary, opts)
% Print KPI
if ~isempty(summary.kpi.meanThroughput)
    fprintf('KPI Summary: mean Tput=%.3f, peak Tput=%.3f, mean BER=%.3e, mean FER=%.3e\n', ...
        summary.kpi.meanThroughput, summary.kpi.peakThroughput, summary.kpi.meanBer, summary.kpi.meanFer);
else
    fprintf('KPI Summary: not available (no downlink results)\n');
end

% Print per-frame arrays if present
if ~isempty(summary.downlinkResults)
    tput = summary.downlinkResults.userResults.throughput.values;
    ber = summary.downlinkResults.userResults.BERCoded.values;
    fer = summary.downlinkResults.userResults.FER.values;
    fprintf('Throughput per frame:\n'); disp(tput(:).');
    fprintf('BER per frame:\n'); disp(ber(:).');
    fprintf('FER per frame:\n'); disp(fer(:).');
else
    tput = []; ber = []; fer = [];
end

if ~opts.enablePlots
    return;
end

ensureFolder(opts.outputDir);
% Plot throughput/BER/FER bars if available
if ~isempty(summary.downlinkResults)
    figure('Name','Throughput per frame'); bar(tput); title('Throughput per frame'); xlabel('Frame'); ylabel('Throughput');
    saveas(gcf, fullfile(opts.outputDir,'throughput.png'));

    figure('Name','BER per frame'); bar(ber); title('BER per frame'); xlabel('Frame'); ylabel('BER');
    saveas(gcf, fullfile(opts.outputDir,'ber.png'));

    figure('Name','FER per frame'); bar(fer); title('FER per frame'); xlabel('Frame'); ylabel('FER');
    saveas(gcf, fullfile(opts.outputDir,'fer.png'));
end

% Waveform plots (first frame)
if ~isempty(summary.txFrames)
    tx = summary.txFrames{1};
    figure('Name','TX waveform (real)'); plot(real(tx)); title('TX waveform (real)'); xlabel('Sample'); ylabel('Amplitude');
    saveas(gcf, fullfile(opts.outputDir,'tx_waveform.png'));
end
if ~isempty(summary.rxFrames) && ~isempty(summary.rxFrames{1})
    rx = summary.rxFrames{1};
    figure('Name','RX waveform (real)'); plot(real(rx)); title('RX waveform (real)'); xlabel('Sample'); ylabel('Amplitude');
    saveas(gcf, fullfile(opts.outputDir,'rx_waveform.png'));
    % Spectrum
    [pxx,f] = pwelch(rx(:,1),[],[],[],summary.parameters.samplingRate,'centered');
    figure('Name','RX Spectrum'); plot(f/1e6,10*log10(pxx)); xlabel('Frequency (MHz)'); ylabel('PSD (dB)'); title('RX Spectrum');
    saveas(gcf, fullfile(opts.outputDir,'rx_spectrum.png'));
    % Constellation (scatter a subset)
    nScat = min(2000, numel(rx(:,1)));
    figure('Name','RX constellation (raw samples)'); scatter(real(rx(1:nScat,1)), imag(rx(1:nScat,1)), '.'); grid on;
    xlabel('I'); ylabel('Q'); title('RX constellation (raw samples)');
    saveas(gcf, fullfile(opts.outputDir,'rx_constellation.png'));
end
end

%% ------------------------------------------------------------------------
function reportSweep(results, opts)
% Collect sweep KPIs
names = {};
tput = [];
ber = [];
fer = [];
for i = 1:numel(results)
    if isempty(results{i})
        continue;
    end
    names{end+1} = results{i}.config.name; %#ok<AGROW>
    tput(end+1) = results{i}.kpi.meanThroughput; %#ok<AGROW>
    ber(end+1) = results{i}.kpi.meanBer; %#ok<AGROW>
    fer(end+1) = results{i}.kpi.meanFer; %#ok<AGROW>
end

if isempty(names)
    fprintf('Sweep: no valid results.\n');
    return;
end

namesStr = string(names);
T = table(namesStr', tput', ber', fer', 'VariableNames', {'Config','MeanThroughput','MeanBER','MeanFER'});
disp('Sweep KPI Table:'); disp(T);

% Save CSV
ensureFolder(opts.outputDir);
writetable(T, fullfile(opts.outputDir, 'sweep_kpi.csv'));

% Plot throughput comparison
figure('Name','Sweep Throughput Comparison'); bar(categorical(namesStr), tput);
xlabel('Config'); ylabel('Mean Throughput'); title('Throughput comparison across configs');
saveas(gcf, fullfile(opts.outputDir, 'sweep_throughput.png'));

% Report best config
[bestTput, idx] = max(tput);
fprintf('Sweep best config: %s (MeanThroughput=%.3f, MeanBER=%.3e, MeanFER=%.3e)\n', ...
    namesStr(idx), bestTput, ber(idx), fer(idx));
end
