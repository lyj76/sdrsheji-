%% The Vienna 5G Link Level Simulator v1.1
% www.tc.tuwien.ac.at/vccs
% Please refer to the user manual to get familiar with the simulator structure and mechanics. 
% For any questions, consider our forum www.tc.tuwien.ac.at/forum.

% Main simulator script

close all;
clear;
clc;

%% Setup 初始化
% select scenario
%选取一个场景
simulationScenario = 'LTEAcompliant';         % select a simulation scenario:
                                                % 'genericScenario' 默认的通用场景
                                                % 'LTEAcompliant' 长期演进（参数较为简单）
                                                % 'multiLink' 
                                                % 'flexibleNumerology'
                                                % 'NOMA'
                                                                             
% load parameters according to scenario                                               
simParams = Parameters.SimulationParameters( simulationScenario ); %存储本次仿真的参数对象
dim = simParams.modulation.nSymbolsTotal*simParams.modulation.numerOfSubcarriers;

% generate network topology and links between nodes 生成网络拓扑和节点之间的链接
[Links, BS, UE] = Topology.getTopology(simParams);

nBS         = length(BS);
nUE         = length(UE);
dimLinks    = length(Links);
nFrames     = simParams.simulation.nFrames;

% initialize result variables 初始化
perSweepResults         = cell(length(simParams.simulation.sweepValue), nFrames);
simResults              = cell(1, length(simParams.simulation.sweepValue));
averageFrameDuration    = 0;

%% Simulation loop 仿真循环
startTime   = tic; %计时
myCluster   = parcluster('local');
NumWorkers  = myCluster.NumWorkers;
fprintf(['------- Started -------', '\n']);

% loop over sweep parameter 遍历扫描参数
for iSweep = 1:length(simParams.simulation.sweepValue) % this may be 'for' or 'parfor'
    % update sweep value 更新
    simParams.UpdateSweepValue(iSweep); 
    
    % based on the updated sweep parameter, regenerate the network 重新生成网络
    [Links, BS, UE] = Topology.getTopology(simParams);

    % Objects initialization should be peformed here 对象初始化
    Links = simParams.initializeLinks(Links, BS, UE); 
    
    % save average frame duration 保存平均帧持续时间
    if iSweep == 1
        averageFrameDuration(iSweep) = simParams.simulation.averageFrameDuration;
    end
    
    % Prepare per sweep value results 初始化，存储每次扫描后的结果
    perSweepResults = cell(dimLinks, dimLinks, nFrames);
    
    %PDP = zeros(1024,1);
    for iFrame = 1:nFrames
        % link adaptation 链路适配
        % update all links 更新所有链路
        nBS = length( BS );
        L   = length(Links);
        for iBS = 1:nBS
            for iLink = 1:L
                % Downlink 下行链路
                if simParams.simulation.simulateDownlink && ~isempty(Links{BS{iBS}.ID, iLink}) && strcmp(Links{BS{iBS}.ID, iLink}.Type, 'Primary')
                    Links{BS{iBS}.ID, iLink}.updateLink( simParams, Links, iFrame );
                elseif simParams.simulation.simulateDownlink && ~isempty(Links{BS{iBS}.ID, iLink}) && strcmp(Links{BS{iBS}.ID, iLink}.Type, 'Interference')
                    Links{BS{iBS}.ID, iLink}.Channel.NewRealization(iFrame);
                end
                % Uplink 上行链路
                if simParams.simulation.simulateUplink && ~isempty(Links{iLink, BS{iBS}.ID}) && strcmp(Links{iLink, BS{iBS}.ID}.Type, 'Primary')
                    Links{iLink, BS{iBS}.ID}.updateLink( simParams, Links,iFrame );
                elseif simParams.simulation.simulateUplink && ~isempty(Links{iLink, BS{iBS}.ID}) && strcmp(Links{iLink, BS{iBS}.ID}.Type, 'Interference')
                    Links{iLink, BS{iBS}.ID}.Channel.NewRealization(iFrame);
                end
            end
        end
        
        %% Downlink
        if simParams.simulation.simulateDownlink
        % All BSs generate their transmit signal for this frame 所有基站为这个帧生成它们的传输信号
            for iBS = 1:nBS
                BS{iBS}.generateTransmitSignal(Links);
            end
            
            for iUE = 1:nUE
                UEID = UE{iUE}.ID;
                primaryLink = Links{UE{iUE}.TransmitBS(1), UEID};  
                if primaryLink.isScheduled
                   primaryLink.generateReceiveSignal();
                   
                    % primaryLink.ReceiveSignal = primaryLink.TransmitSignal;
                    UETotalSignal = primaryLink.ReceiveSignal;

                    % Collect signals from all other BSs 收集其他所有基站的信号
                    for iBS = 2:length(UE{iUE}.TransmitBS)
                        currentLink = Links{UE{iUE}.TransmitBS(iBS), UEID};
                        currentLink.generateReceiveSignal();
                        UETotalSignal = Channel.addSignals(UETotalSignal, currentLink.ReceiveSignal);
                    end
                    % correct signal length 收集信号长度
                    UETotalSignal = Channel.correctSignalLength(UETotalSignal, primaryLink.Modulator.WaveformObject.Nr.SamplesTotal);
                    

                    %receive = 20*log10(abs(fft(UETotalSignal)));
                    % plot signal spectrum 绘制信号频谱
%                     figure(13)
%                     plot( (1:primaryLink.Modulator.WaveformObject.Nr.SamplesTotal).' ...
%                         /primaryLink.Modulator.WaveformObject.Nr.SamplesTotal * simParams.modulation.samplingRate, ...
%                         20*log10(abs(fft(UETotalSignal))))
% %                     (1:primaryLink.Modulator.WaveformObject.Nr.SamplesTotal).' /primaryLink.Modulator.WaveformObject.Nr.SamplesTotal * simParams.modulation.samplingRate
%                     xlabel('f in Hz');
%                     ylabel('Signal Power in dB');
%                      %xlim([0 5e6]);
%                      %ylim([-150 -50]);
%                     grid on;
%                     print('-dpdf','PSD_comp_','-bestfit')
%                     title('receive signal spectrum')
                    
                    % add noise 添加噪声
                    UETotalSignal = UETotalSignal + Channel.AWGN( simParams.phy.noisePower, length(UETotalSignal), UE{iUE}.nAntennas );
                    
                    % process received signal 
                    UE{iUE}.processReceiveSignal(UETotalSignal, Links, simParams);

                    % Collect the results which is now stored in the primary link
                    primaryLink.calculateSNR(simParams.constants.BOLTZMANN, simParams.phy.temperature);
                    perSweepResults{UE{iUE}.TransmitBS(1), UEID, iFrame} = primaryLink.getResults(simParams.simulation.saveData);
                end

                % for i = 1:130
                %     CIRi = ifft(primaryLink.Modulator.Channel(:,i));
                %     PDP = PDP + (abs(CIRi).^2);
                % end
            end
            
         end 
         %% Uplink
         if simParams.simulation.simulateUplink
            % All UEs generate their transmit signal for this frame
            for iUE = 1:nUE
                UE{iUE}.generateTransmitSignal(Links);
            end
            for iBS = 1:nBS
                BSID = BS{iBS}.ID;
                BSTotalSignal = [];
                % Collect signals from all users transmitting to this BS
                % (both primary and interfering users)
                for iUE = 1:length(BS{iBS}.TransmitUE)
                    currentLink = Links{BS{iBS}.TransmitUE(iUE), BSID};
                    if strcmp(currentLink.Type, 'Primary')
                        signalLength = currentLink.Modulator.WaveformObject.Nr.SamplesTotal;
                    end
                    if currentLink.isScheduled
                        currentLink.generateReceiveSignal();                      
                        BSTotalSignal = Channel.addSignals(BSTotalSignal, currentLink.ReceiveSignal);
                    end
                end
                % correct signal length
                BSTotalSignal = Channel.correctSignalLength(BSTotalSignal, signalLength);      
                
                % add noise
                BSTotalSignal = BSTotalSignal + Channel.AWGN( simParams.phy.noisePower, length(BSTotalSignal), BS{iBS}.nAntennas );
                
                % process received signal
                BS{iBS}.processReceiveSignal(BSTotalSignal, Links, simParams);

                % Collect the results
                for iUE = 1:length(BS{iBS}.TransmitUE)
                    currentLink = Links{BS{iBS}.TransmitUE(iUE), BSID};
                    if currentLink.isScheduled && strcmp(currentLink.Type, 'Primary')
                        currentLink.calculateSNR(simParams.constants.BOLTZMANN, simParams.phy.temperature);
                        perSweepResults{BS{iBS}.TransmitUE(iUE), BSID, iFrame} = currentLink.getResults(simParams.simulation.saveData);
                    end
                end  
            end
        end
        %% Device-to-Device
%         if simParams.simulation.simulateD2D
%            % Not yet implemented, but it can be done in a similar fashion
%         end

        %% Time calculation
        % Some basic time calculation.
        intermediateTime = tic;
        if mod(iFrame, 20) == 0
            fprintf('Sweep: %i/%i, Frame: %i/%i, approx. %.0fs left\n', iSweep,length(simParams.simulation.sweepValue),iFrame,nFrames, double(intermediateTime-startTime)*1e-6*(nFrames*length(simParams.simulation.sweepValue)-(iFrame+(iSweep-1)*nFrames))/(iFrame+(iSweep-1)*nFrames));
        end
    end % for iFrame
    simResults{iSweep} = perSweepResults;
end % parfor iSweep

    % %在帧循环结束后加入PDP计算
    % PDP = PDP./(sum(PDP));
    % 
    % %计算得到PDP后，加入FCF计算
    % PDP_normal = PDP;
    % df = 1/(primaryLink.Channel.Nr.SamplesTotal*primaryLink.Channel.PHY.dt);
    % FrequencyCorrelation = fft([PDP_normal;zeros(primaryLink.Channel.Nr.SamplesTotal-length(PDP_normal),1)]);
    % FrequencyCorrelation = circshift(FrequencyCorrelation,[ceil(primaryLink.Channel.Nr.SamplesTotal/2) 1]);
    % Frequency = ((1:primaryLink.Channel.Nr.SamplesTotal)-ceil(primaryLink.Channel.Nr.SamplesTotal/2)-1)*df;
%% post process simulation results
if simParams.simulation.simulateDownlink
   downlinkResults = Results.SimulationResults( nFrames, length(simParams.simulation.sweepValue), nBS, nUE, averageFrameDuration, 'downlink' );
    downlinkResults.collectResults( simResults, UE );
    downlinkResults.postProcessResults();
end
   %% post process simulation results
if simParams.simulation.simulateDownlink
    downlinkResults = Results.SimulationResults( nFrames, length(simParams.simulation.sweepValue), nBS, nUE, averageFrameDuration, 'downlink' );
    downlinkResults.collectResults( simResults, UE );
    downlinkResults.postProcessResults();
    % plot results
    if sum(simParams.simulation.plotResultsFor) ~= 0
        f=1:20;
        BER = downlinkResults.userResults.BERCoded.values;
        FER = downlinkResults.userResults.FER.values;
        Throughput = downlinkResults.userResults.throughput.values;
        figure(1)
        bar(f,BER)
        xlabel('frame')
        ylabel('BER')
        title('误码率性能');
        figure(2)
        bar(f,FER)
        xlabel('frame')
        ylabel('FER')
        title('误帧率性能');
        figure(3)
        bar(f,Throughput)
        xlabel('frame')
        ylabel('Throughput')
        title('吞吐量性能');


        % figure(9);
        % plot((1:primaryLink.Modulator.WaveformObject.Nr.SamplesTotal).' / ...
        %     primaryLink.Modulator.WaveformObject.Nr.SamplesTotal * simParams.modulation.samplingRate, ...
        %     20*log10(abs(fft(primaryLink.TransmitSignal))))
        % xlabel('f in Hz');
        % ylabel('Signal Power in dB');
        % %xlim([0 1e7]);
        % %ylim([-50 50]);
        % grid on;
        % print('-dpdf','PSD_comp_','-bestfit')
        % title('transmit signal spectrum')

        % figure(10);
        % n_sub = Links{1, 2}.Modulator.WaveformObject.Nr.Subcarriers;
        % n_sym = Links{1, 2}.Modulator.WaveformObject.Nr.MCSymbols;
        % channel_LS = Links{1, 2}.Modulator.Channel;
        % Y = 1:n_sub;
        % X = 1:n_sym;
        % Z = 10*log10(abs(channel_LS));
        % surf;
        % xlabel('OFDM symbols')
        % ylabel('Subcarrier Index')
        % zlabel('Estimated Channel Frequency Response (dB)');

        % figure(11)
        % for ii = 1:n_sym
        %     plot(Z(:,ii));
        %     hold on
        % end
        % xlabel('Subcarrier Index')
        % ylabel('Estimated Channel Frequency Response (dB)');
        % hold off
        % 
        % figure(12)
        % for jj = 1:n_sub
        %     plot(Z(jj,:));
        %     hold on
        % end
        % xlabel('OFDM symbols')
        % ylabel('Estimated Channel Frequency Response (dB)');

        % PlotFrequencyCorrelation(primaryLink.Channel,1);
        % PlotPowerDelayProfile(primaryLink.Channel);
    end
end
if simParams.simulation.simulateUplink
    uplinkResults = Results.SimulationResults( nFrames, length(simParams.simulation.sweepValue), nBS, nUE, averageFrameDuration, 'uplink' );
    uplinkResults.collectResults( simResults, UE );
    uplinkResults.postProcessResults();
    % plot results
    if sum(simParams.simulation.plotResultsFor) ~= 0
        Results.plotResults( uplinkResults, 'uplink', simParams, UE, BS );
    end
end

%% save results
% generate timestamp
tmpStr = datestr(now);
tmpStr = strrep(tmpStr,':','_');
timeStamp = strrep(tmpStr,' ','_');
% save results (complete workspace)
save(['./results/results_',timeStamp]);

fprintf(['------- Done -------', '\n']);
toc(startTime);
%% Function
        function [FrequencyCorrelation,Frequency] = GetFrequencyCorrelation(obj)
            % returns the frequency-autocorrelation function of the channel.
            
            df = 1/(obj.Nr.SamplesTotal*obj.PHY.dt);
            
            FrequencyCorrelation = fft([obj.Implementation.PowerDelayProfileNormalized;zeros(obj.Nr.SamplesTotal-length(obj.Implementation.PowerDelayProfileNormalized),1)]);
            FrequencyCorrelation = circshift(FrequencyCorrelation,[ceil(obj.Nr.SamplesTotal/2) 1]);
            
            Frequency =((1:obj.Nr.SamplesTotal)-ceil(obj.Nr.SamplesTotal/2)-1)*df;
        end
        function PlotFrequencyCorrelation(obj,FrequencySpacing)
            % Plot the frequency correlation. The input argument represents
            % the time-spacing and plots discrete points at multiples
            % of the time-spacing (only for presentational purpose)
            
            [FrequencyCorrelation,Frequency]=obj.GetFrequencyCorrelation;
            figure(3);
            plot(Frequency,abs(FrequencyCorrelation));
            ylabel('|Frequency Correlation|');
            xlabel('Frequency (Hz)');
            
            if not(exist('FrequencySpacing','var'))
                FrequencyPointSymbols = (-ceil(Frequency(end)/FrequencySpacing):ceil(Frequency(end)/FrequencySpacing))*FrequencySpacing;
                hold on;
                Plot1 = stem(FrequencyPointSymbols,abs(interp1(Frequency,FrequencyCorrelation,FrequencyPointSymbols)),'black');
                legend(Plot1,{'FrequencySpacing'});
            end
        end
        function PlotPowerDelayProfile(obj)
            % Plot the desired power delay profile and the chosen power delay
            % profile, limited by the sampling rate
            
            Tau = (0:(length(obj.Implementation.PowerDelayProfileNormalized))-1)*obj.PHY.dt;
            PowerDelayProfile = obj.Implementation.PowerDelayProfileNormalized;
            %if nargout==1
                figure(4)
                DesiredTemp = 10.^(obj.PHY.DesiredPowerDelayProfiledB(1,:)/10);
                DesiredTemp = DesiredTemp/sum(DesiredTemp);
                RMSDelaySpread = obj.GetRmsDelaySpread;
                stem(obj.PHY.DesiredPowerDelayProfiledB(2,:)/1e-6,DesiredTemp,'-x red');
                hold on;
                stem(Tau/1e-6,PowerDelayProfile,'-o  blue');
                xlim([-obj.PHY.dt/1e-6/2 Tau(end)/1e-6+obj.PHY.dt/1e-6/2]);
                ylim([0 1]);
                xlabel('Delay [µs]');
                ylabel('Power Delay Profile');
                title(['RMS Delay Spread: ' num2str(round(RMSDelaySpread/1e-9)) 'ns']);
                legend({'Desired Delay Taps','Chosen Delay Taps (due to sampling)'});  
            %end
        end
       
        
