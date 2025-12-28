%% 接收端
    UETotalReceiveSignal_temp = load('TransmitSignal.mat');%具体需要根据usrp接收到的数据进行修改
    UETotalTransmitSignal_temp = load('TransmitSignal.mat');
    UETotalTransmitSignal_temp_1 = struct2cell(UETotalTransmitSignal_temp);
    UETotalReceiveSignal_temp_1 = struct2cell(UETotalReceiveSignal_temp);
    UETotalTransmitSignal = UETotalTransmitSignal_temp_1{1,1};
    UETotalReceiveSignal = UETotalReceiveSignal_temp_1{1,1};
    [corr,index] = xcorr(UETotalReceiveSignal,zcSequence);
    [max_corr_val,~] = max(abs(corr));
    % figure;
    % plot(index/15.36e6, abs(corr)); title('信道同步性能');
    % xlabel('时间延迟(s)');
    % ylabel('相关度');
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
                    receive_frame_signal = UETotalReceiveSignal(frame_start_pos(iFrame) + zclength + 1:frame_start_pos(iFrame + 1));
                    transmit_frame_signal = UETotalTransmitSignal(frame_start_pos(iFrame) + zclength + 1:frame_start_pos(iFrame + 1));
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
 % parfor iSweep

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