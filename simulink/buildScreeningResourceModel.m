function buildScreeningResourceModel(modelName)
% BUILDSCREENINGRESOURCEMODEL  Phase 6: builds a Simulink model
%   programmatically (run this once; it creates and saves a .slx file
%   you can then open, tweak visually, and simulate/screenshot for the
%   judges). Models a simplified district-level screening queue:
%
%       image arrival rate --> [ - ] --> backlog (integrator, saturated at 0)
%       service rate (1/proc_time) --/
%
%   Outputs: backlog over time (queue length) and utilization, so you
%   can argue optimal ophthalmologist review capacity for a given
%   district patient volume — directly answers pillar 5 of the problem
%   statement.
%
%   buildScreeningResourceModel('DR_ScreeningResourceModel')

    arguments
        modelName (1,1) string = "DR_ScreeningResourceModel"
    end

    if bdIsLoaded(modelName)
        close_system(modelName, 0);
    end
    new_system(modelName);
    open_system(modelName);

    % --- Image arrival rate: step/constant representing images/hour
    %     arriving from field cameras (tune for district volume, e.g.
    %     100,000 patients/year -> ~11-12 images/hour average, spiky) ---
    add_block('simulink/Sources/Pulse Generator', modelName + "/ImageArrivalRate", ...
        'Amplitude', '15', 'Period', '1', 'PulseWidth', '60', ...
        'Position', [30 40 90 70]);

    % --- Processing rate: AI pipeline throughput (images/hour the
    %     automated pipeline + quality/enhancement/classification/
    %     Grad-CAM stages can clear). Tune from your own measured
    %     per-image runtime once Phase 4 is trained. ---
    add_block('simulink/Sources/Constant', modelName + "/ProcessingCapacity", ...
        'Value', '40', 'Position', [30 130 90 160]);

    % --- Ophthalmologist review capacity bottleneck: images/hour a
    %     human reviewer can clear at <30s/image per the explainability
    %     requirement (pillar 4) -> ~120 images/hour per reviewer,
    %     scaled down here for a small district clinic ---
    add_block('simulink/Sources/Constant', modelName + "/ReviewCapacity", ...
        'Value', '20', 'Position', [30 200 90 230]);

    % --- Effective service rate = min(processing capacity, review capacity) ---
    add_block('simulink/Math Operations/MinMax', modelName + "/EffectiveServiceRate", ...
        'Function', 'min', 'Inputs', '2', 'Position', [150 150 210 200]);

    % --- Net rate = arrivals - effective service rate ---
    add_block('simulink/Math Operations/Sum', modelName + "/NetRate", ...
        'Inputs', '+-', 'Position', [270 80 320 130]);

    % --- Backlog = integral of net rate, saturated at 0 (can't have
    %     negative queue) ---
    add_block('simulink/Continuous/Integrator', modelName + "/Backlog", ...
        'Position', [370 80 420 130]);
    add_block('simulink/Discontinuities/Saturation', modelName + "/NonNegativeBacklog", ...
        'LowerLimit', '0', 'UpperLimit', 'inf', 'Position', [440 80 490 130]);

    % --- Scope to visualize backlog + utilization over simulated time ---
    add_block('simulink/Sinks/Scope', modelName + "/BacklogScope", ...
        'Position', [550 80 600 130], 'NumInputPorts', '1');
    add_block('simulink/Sinks/To Workspace', modelName + "/BacklogToWorkspace", ...
        'VariableName', 'backlogOverTime', 'Position', [550 160 640 190]);

    % --- Wiring ---
    add_line(modelName, 'ProcessingCapacity/1', 'EffectiveServiceRate/1', 'autorouting', 'on');
    add_line(modelName, 'ReviewCapacity/1', 'EffectiveServiceRate/2', 'autorouting', 'on');
    add_line(modelName, 'ImageArrivalRate/1', 'NetRate/1', 'autorouting', 'on');
    add_line(modelName, 'EffectiveServiceRate/1', 'NetRate/2', 'autorouting', 'on');
    add_line(modelName, 'NetRate/1', 'Backlog/1', 'autorouting', 'on');
    add_line(modelName, 'Backlog/1', 'NonNegativeBacklog/1', 'autorouting', 'on');
    add_line(modelName, 'NonNegativeBacklog/1', 'BacklogScope/1', 'autorouting', 'on');
    add_line(modelName, 'NonNegativeBacklog/1', 'BacklogToWorkspace/1', 'autorouting', 'on');

    set_param(modelName, 'StopTime', '24'); % simulate a 24-hour operational day

    save_system(modelName, modelName + ".slx");
    fprintf('Simulink model saved: %s.slx\n', modelName);
    fprintf('Run with: sim(''%s''); then plot(backlogOverTime) to show judges queue behavior.\n', modelName);
    fprintf('Tune ProcessingCapacity/ReviewCapacity constants against your real measured throughput.\n');
end
