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
Link_total = cell(nFrames,1);
TransmitSignalTotal = [];
ReceiveSignalTotal = [];
%生成zc序列
zclength = 139;
zcseed = 25;
zcSequence = zadoffChuSeq(zcseed,zclength);
noise_length = 200;
%simParams.phy.noisePower = 14;
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

                %总的发射信号
                TransmitSignalTotal = [TransmitSignalTotal;primaryLink.TransmitSignal];
                %保存10帧的所有数据
                my_Links = primaryLink;
                save('Link_total.mat',"my_Links");
            end
            Link_total_temp = load("Link_total.mat");
            Link_total{iFrame,1} = struct2cell(Link_total_temp);
         end 
    end % for iFrame
end
    save('TransmitSignal',"TransmitSignalTotal");