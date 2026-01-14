%% The Vienna 5G Link Level Simulator v1.1
% www.tc.tuwien.ac.at/vccs
% Please refer to the user manual to get familiar with the simulator structure and mechanics. 
% For any questions, consider our forum www.tc.tuwien.ac.at/forum.

% Main simulator script

close all;
clear;
clc;
rng(42);
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
Link_total = cell(nFrames,1);
TransmitSignalTotal = [];
ReceiveSignalTotal = [];
%生成zc序列
zclength = 139;
zcseed = 25;
zcSequence = zadoffChuSeq(zcseed,zclength);
simParams.phy.noisePower = 14;
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
        
        %% 发送端
        if simParams.simulation.simulateDownlink
        % All BSs generate their transmit signal for this frame 所有基站为这个帧生成它们的传输信号
            for iBS = 1:nBS
                BS{iBS}.generateTransmitSignal(Links);
            end
            for iUE = 1:nUE
                UEID = UE{iUE}.ID;
                primaryLink = Links{UE{iUE}.TransmitBS(1), UEID};
                Signal_length = length(Links{UE{iUE}.TransmitBS(1), UEID}.TransmitSignal);
                
                %将zc序列插入每帧开头
                primaryLink.TransmitSignal = [zcSequence;primaryLink.TransmitSignal];
                primaryLink.TransmitSignal = primaryLink.TransmitSignal + Channel.AWGN( simParams.phy.noisePower, ...
                                                        length(primaryLink.TransmitSignal), UE{1}.nAntennas );
                noise_signal = Channel.AWGN( simParams.phy.noisePower, 200, UE{1}.nAntennas);
                 
                temp = [noise_signal;primaryLink.TransmitSignal];
                primaryLink.TransmitSignal = temp;
                TransmitSignalTotal = [TransmitSignalTotal;primaryLink.TransmitSignal];
    
                % %分别经过信道？
                % pre_seq = primaryLink.TransmitSignal(1:length(zcSequence)+length(noise_signal));
                % real_sig = primaryLink.TransmitSignal(length(zcSequence)+length(noise_signal)+1:end);
                % primaryLink.TransmitSignal = pre_seq;
                % primaryLink.generateReceiveSignal();
                % pre_seq_receive = primaryLink.ReceiveSignal;
                % 
                % primaryLink.TransmitSignal = real_sig;
                % primaryLink.generateReceiveSignal();
                % real_sig_receive = primaryLink.ReceiveSignal;
                % primaryLink.ReceiveSignal = [pre_seq_receive;real_sig_receive];
                % primaryLink.TransmitSignal = temp;
                % ReceiveSignalTotal = [ReceiveSignalTotal;primaryLink.ReceiveSignal];

                %保存10帧的所有数据
                my_Links = primaryLink;
                save('Link_total.mat',"my_Links");
            end
            Link_total_temp = load("Link_total.mat");
            Link_total{iFrame,1} = struct2cell(Link_total_temp);
         end 
    end % for iFrame
    %% 接收端
    ZC_OK = 0;
    UETotalReceiveSignal = TransmitSignalTotal;
    UETotalTransmitSignal = TransmitSignalTotal;
    [corr,index] = xcorr(UETotalReceiveSignal,zcSequence);
    [max_corr_val,~] = max(abs(corr));
    figure;
    plot(index, abs(corr)); title('信道同步性能');
    xlabel('时间延迟(s)');
    ylabel('相关度');
    %找到最大峰值的点
    threshold = 0.8*max_corr_val;
    peakIdx = find(abs(corr)>threshold);
    delay_offset = peakIdx - length(UETotalReceiveSignal);
    frame_start_pos = delay_offset + 1;
    num_Frame = length(frame_start_pos);
    for iFrame = 1:num_Frame
        for iUE = 1:nUE
            UEID = UE{iUE}.ID;
            Links{UE{iUE}.TransmitBS(1), UEID} = Link_total{iFrame,1}{1};
            primaryLink = Links{UE{iUE}.TransmitBS(1), UEID};  
            if primaryLink.isScheduled
                if iFrame == num_Frame
                    receive_frame_signal = UETotalReceiveSignal(frame_start_pos(iFrame) + zclength:end);
                    transmit_frame_signal = UETotalTransmitSignal(frame_start_pos(iFrame) + zclength:end);
                else
                    receive_frame_signal = UETotalReceiveSignal(frame_start_pos(iFrame) + zclength + 1:frame_start_pos(iFrame + 1) - length(noise_signal));
                    transmit_frame_signal = UETotalTransmitSignal(frame_start_pos(iFrame) + zclength + 1:frame_start_pos(iFrame + 1) - length(noise_signal));
                end
                %检测同步性能
                if length(receive_frame_signal) == Signal_length
                    ZC_OK = ZC_OK + 1;
                end
                % process received signal 
                Links{UE{iUE}.TransmitBS(1), UEID}.TransmitSignal = transmit_frame_signal;
                Links{UE{iUE}.TransmitBS(1), UEID}.ReceiveSignal = receive_frame_signal;

                UE{iUE}.processReceiveSignal(receive_frame_signal, Links, simParams);

                % Collect the results which is now stored in the primary link
                primaryLink.calculateSNR(simParams.constants.BOLTZMANN, simParams.phy.temperature);
                perSweepResults{UE{iUE}.TransmitBS(1), UEID, iFrame} = primaryLink.getResults(simParams.simulation.saveData);
            end
        end 
        %% Time calculation
        % Some basic time calculation.
        intermediateTime = tic;
        if mod(iFrame, 20) == 0
            fprintf('Sweep: %i/%i, Frame: %i/%i, approx. %.0fs left\n', iSweep,length(simParams.simulation.sweepValue),iFrame,nFrames, double(intermediateTime-startTime)*1e-6*(nFrames*length(simParams.simulation.sweepValue)-(iFrame+(iSweep-1)*nFrames))/(iFrame+(iSweep-1)*nFrames));
        end        
    end
    simResults{iSweep} = perSweepResults;
   % fprintf('Channel style:%s, the numble of Frame after synchronization is %d, success rate is %f\n',simParams.channel.powerDelayProfile,num_Frame,ZC_OK/10);
    fprintf('NoisePower:%f, the numble of Frame after synchronization is %d, success rate is %f\n',simParams.phy.noisePower,num_Frame,ZC_OK/10);

end % parfor iSweep

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
        f=1:10;
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
        sym_success = ZC_OK / nFrames;
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
% % generate timestamp
% tmpStr = datestr(now);
% tmpStr = strrep(tmpStr,':','_');
% timeStamp = strrep(tmpStr,' ','_');
% % save results (complete workspace)
% save(['./results/results_',timeStamp]);
% 
% fprintf(['------- Done -------', '\n']);
% toc(startTime);