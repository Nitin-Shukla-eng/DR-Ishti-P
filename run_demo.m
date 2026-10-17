   % Launches the DR-Ishti screening dashboard
   rootDir = fileparts(mfilename('fullpath'));
   cd(rootDir);
   addpath(genpath(fullfile(rootDir, 'src')));
   addpath(fullfile(rootDir, 'app'));
   DRScreeningApp