function [traindata, testdata] = dataGenerator( par )

%
% function [traindata, testdata] = dataGenerator( par )
%
% Generates data for testing machine learning algorithms, especially feature
% selection algorithms.
%
% TODO Does not yet generate redundant variables.
% 
%----------------------------------------------------------
% Input: structure 'par'.
%
% par must have fields:
%
% dependency - 'linear' or 'nonlinear' (see function nonlinearGenerator)
% N  - number of samples generated
% n  - number of relevant variables from which target is generated
% Kn - number of additional noise variables concatenated to data
% maxClasses - 0 regression, >0 discretize target to max maxClasses levels
% fileFormat - cell array or one of {'R','x','none','arff'}
%              (see function dWriteR    for 'R' and 'x')
%              (see function dWriteArff for 'arff')

% 
% par may have fields:
%
% O -  number of target variables [1]
% seed - random number generator seed [generated from time]
% sets - how many data sets to generate [1]
% missing - fraction of missing values [0]
% randomizeTarget -  add noise to target(s) with var 'randomizeTarget' [0]
% mixedType - discretize this fraction of the input variables [0]
% maxLevels - max num discrete levels in above [32]
% testFraction - fraction of each set written to a test file [0]
% L - nonlinear: number of functions added together to construct the  target [20]
% P - linear: O x n dependency matrix (=importances) [generated by rand]
% sampleHeader - generate a header for samples (always for features) [0]
% 
% 
%----------------------------------------------------------
% Output:
% traindata - a cell array of structures containing generated set(s)
% testdata  - if testFraction>0, a cell array of structures containing 
%             the test portion(s) of the generated set(s)
%             
% fields in both:
% data - double N x (n+Kn+O) matrix, samples as rows, variables as columns
% head - names of generated variables, relevant Ixx, noise Nxx, target Oxx,
%        where xx is the index of the variable. If discretized, the name will
%        have _dzz appended, where zz is the number of levels
% catI - index set of discrete variables
% catLevels - numbers of leveld of the discrete variables
% name - id string encoding some of the parameters
% importances - O x n matrix containing "true" importances of the relevant variables
%----------------------------------------------------------



% Initialize random number generation
if ~isfield(par,'seed'),
    % if seed is not given, generate it from clock
    par.seed = round(sum(100*clock));
end
% set the default random number stream to mersenne twister
RandStream.setDefaultStream( RandStream('mt19937ar', 'Seed', par.seed) );


if ~isfield(par,'O'),
    par.O = 1; % default number of output variables
end
if ~isfield(par,'sampleHeader'),
    par.sampleHeader = 0;
end

% generate a desired number of data sets
if ~isfield(par,'sets'),
    par.sets = 1;
end
for set=1:par.sets,
   
    % dependency between target and relevant variables?
    switch par.dependency,
        
        case 'linear',            
            % is the dependency matrix specified?
            if isfield(par,'P'),
                if size(par.P,1)~=par.O,
                    error('Linear dependency matrix par.P must have %d rows\n',par.O);
                end
                if ~isfield(par,'n'), 
                    % if number of relevant variables is not specified, take it from P
                    par.n = size(par.P,2);
                end                
                if size(par.P,2)~=par.n,
                    warning('Linear dependency matrix par.P has %d columns but %d relevant \nvariables were specified. Setting par.n=%d\n', size(par.P,2), par.n, size(par.P,2) );
                    par.n = size(par.P,2);
                end
            else
                % Random weights given for relevant variables
                par.P = rand(par.O, par.n); 
            end
            
            % target depends on these par.n variables (zero-mean, unit var)
            X = randn(par.N, par.n); 
            Y = X * par.P';   
           
            % TODO it would be nice to be able to specify variable
            % importance in relation to noise variance added to target
            % such as this:
            % Y = X(:,1) + 0.5*X(:,2) + 0.25*X(:,3) + 0.125*X(:,4) + 1.5*randomizeTarget*X(:,5) + randomizeTarget*randn(N,1);
            % Of course the same can be achieved by specifying 'P' and
            % 'randomizeTarget'.
            
        case 'nonlinear',
            [X, Y, par.P] = nonlinearGenerator(par);   
            
         otherwise,
            error('No such dependency [%s]!', par.dependency );
    end
    
    
    % add random noise to target variable(s)
    if isfield(par,'randomizeTarget') && par.randomizeTarget>0,
        Y = Y + par.randomizeTarget*randn(size(Y));
    end
    
    % Join relevant variables with irrelevant noise variables
    X = [X randn(par.N,par.Kn)];
    
    % discretize targets to create a classification problem
    if par.maxClasses>0, 
        [Y, dYi,levelsY] = discretize(Y, 1,  par.maxClasses); % rnd number of classes
    else
        dYi=[]; levelsY=[];
    end

    % discretize input variables
    if isfield(par,'mixedType') && par.mixedType>0, 
        if ~isfield(par,'maxLevels'),
            par.maxLevels = 32;
        end
        origX = X;
        [X,dXi,levels] = discretize(X, par.mixedType, par.maxLevels); 
    else
        dXi=[]; levels=[];
    end
    
    % Simulate missing values
    if isfield(par,'missing') && par.missing>0,
        numElements = (par.n+par.Kn)*par.N;
        toDelete = randperm( numElements );
        toDelete = toDelete( 1:round( par.missing*numElements ) );
        X( toDelete ) = NaN;
    end
    
    % concatenate input and target to X
    dXi =[ dXi, dYi+size(X,2) ];
    levels = [levels, levelsY];
	X = [X Y]; 

    % generate variable names
    head = {};
    for i=1:par.n,
        head = [head, {sprintf('I%d',i)} ]; % I='Input'
    end
    for i=1:par.Kn,
        head = [head, {sprintf('N%d',i)} ]; % N='Noise'
    end
    for i=1:par.O,
        head = [head, {sprintf('O%d',i)} ]; % O='Output'
    end
    for i=1:length(dXi),
		% attach the number of levels to names of discretized variables
        head{ dXi(i) } = [ sprintf('%s_d%d', head{ dXi(i) }, levels(i)) ];
    end

    % split data into train and test parts
    if ~isfield(par,'testFraction'),
        par.testFraction = 0;
    end
    trI = round( (1-par.testFraction) * par.N );
    % attach all information into data set structures
    fTr.data = X(1:trI,:);        % first half training 
    fTe.data = X(trI+1:par.N,:);  % second half testing
    fTr.head = head;
    fTe.head = head;
    fTr.catI = dXi;  
    fTe.catI = dXi;
    fTr.catLevels = levels;  
    fTe.catLevels = levels;
    nameId = sprintf('n%d-N%d-Kn%d-cl%d-mixed%.2f-miss%.2f-set%d', par.n, par.N, par.Kn, par.maxClasses, par.mixedType, par.missing, set);
    fTr.name = sprintf('tr-%s', nameId);
    fTe.name = sprintf('te-%s', nameId);
    fTr.importances = par.P;
    fTe.importances = par.P;

    % write output 
    traindata = {};
    testdata  = {};
    if ~iscell(  par.fileFormat ),
         par.fileFormat = { par.fileFormat };
    end
    
    for i=1:length( par.fileFormat ), % save in multiple formats
        
        switch par.fileFormat{i},
            case 'R',
                dWriteR(fTr, [fTr.name '.tsv'], 0, par.sampleHeader);  
                dWriteR(fTe, [fTe.name '.tsv'], 0, par.sampleHeader);
            case 'arff',
                dWriteArff(fTr, [fTr.name '.arff'] ); 
                dWriteArff(fTe, [fTe.name '.arff'] );
            case 'x',
                dWriteR(fTr,[fTr.name '.txt'], 1, par.sampleHeader); 
                dWriteR(fTe,[fTe.name '.txt'], 1, par.sampleHeader);
            case 'none'
                % return data sets in a cell array
                traindata = [traindata, {fTr}];
                testdata  = [testdata, {fTe}];
            otherwise,
                warning('No such format [%s]!', par.fileFormat{i} );
        end
        
    end
end
if par.testFraction==0, 
    % this is an array of empty cells - clean it
    testdata={}; 
end



%%
function [X,F,P] = nonlinearGenerator(parameters)

% [X,F,P] = nonlinearGenerator(parameters)

% Implements a random target function generator described in
%   Jerome H. Friedman, 
%   Greedy Function Approximation: A Gradient Boosting Machine,
%   IMS 1999 Reiz Lecture, page 16.
%   http://www-stat.stanford.edu/~jhf/ftp/trebst.ps

% Input parameters are optional and given as fields of a single argument.
% Possible parameters are (with default values)
%   O - number of target variables (1)
%   N - number of samples generated (1000)
%   n - dimension of input data from which target is generated (10)
%   L - number of functions added together to construct the target (20)
%   X - Nxn matrix of input data. It is possible to use previously generated 
%       input data to generate more output data

% Output:
%   X - Nxn matrix of input variables from which target is generated
%   F - NxO matrix of generated target variables
%   P - Oxn matrix of indicators which input variables were used 

% number of output target variables to be generated
if nargin==1 && isfield(parameters,'O'), O=parameters.O; else O=1; end
% number of samples generated
if nargin==1 && isfield(parameters,'N'), N=parameters.N; else N=1000; end
% number of input variables
if nargin==1 && isfield(parameters,'n'), n=parameters.n; else n=10; end
% number of functions added
if nargin==1 && isfield(parameters,'L'), L=parameters.L; else L=20; end

    
% more or less fixed parameters
a = 0.1; % covariance eigenvalue lower limit
b = 2.0; % covariance eigenvalue upper limit
lambda = 2; % mean of the exponential used in determining the size of a subset

% input variables ~ N(0,I), each row is a sample
if nargin==1 && isfield(parameters,'X'), X=parameters.X; else X=randn(N,n); end
if (size(X,1)~=N)||(size(X,2)~=n), error('Size of given data does not match N or n!'); end
F = zeros(N,O); % target variable(s)
P = zeros(O,n); % approximations of true importances

for o=1:O, 
    al = 2*rand(1,L)-1;  % al ~ U[-1,1]
    % Generate target 
    for l=1:L
        % select interacting input variables zl to generate function l
        r = -lambda * log( rand(1,1)); % r ~ exponential distribution with mean=lambda
        nl = round( 1.5 + r ); % number of input variables, expected value between 3 and 4
        nl = min(n,nl);
        p = randperm(n);
        p = p(1:nl); % random permutation of nl randomly chosen input variables
        P(o,p) = P(o,p) + abs(al(l)); % save information which variables were used
        zl = X(:,p);
    
        % generate mean for Gaussian l
        mean = randn(1,nl); % ~ N(0,I)
        % generate covariance for Gaussian l
        sdl = rand(1,nl)*(b-a)+a; % sdl ~ U[a,b]
        Dl = diag( sdl.^2 );
        Ul = rand(nl,nl);
        Ul = orth(Ul); % random orthonormal matrix
        Vl = Ul*Dl*Ul'; % covariance
    
        % generate the Gaussian
        zl = zl - repmat(mean,N,1); % each row has a data vector
        gl = exp(-0.5* sum((zl*Vl).*zl, 2) );
    
        % add to the current target
        F(:,o) = F(:,o) + al(l)*gl;
    end
end
P = P/L; % scale by number of functions added to get indicators of relative importance



%%
function [X, dXi, levels] = discretize(X, fractionToDiscretize, maxLevels)
[N,d] = size(X);
dd  = round(d*fractionToDiscretize); % discretize this many variables
dXi = randperm(d);
dXi = sort(dXi(1:dd));
levels = zeros(1,dd);
for i=1:dd,
    j = dXi(i);
    [X(:,j), levels(i)] = discretizeColumn(X(:,j), maxLevels);
end


%% 
function [dx, levels] = discretizeColumn(x, maxLevels)
% discretizes between two and maxLevels
dx = zeros(size(x));
xlen = length(x);
sx = sort(x);
low = sx(1)-1;
% levels = 2+round(rand*8);
levels = 2+round( (rand)^2.5*(maxLevels-2)); 
levelsPerm = randperm(levels);
for k=1:levels,
    high = sx( round(k*xlen/levels) );
    dx(  (x>low) & (x<=high)  ) = levelsPerm(k);
    low = high;
end


%%
function dWriteR(f, name, transpose, generateSampleHeader)

% function dWriteR(f, name, transpose, generateSampleHeader)
% 
% Saves the data structure in 'f' into file 'name' in delimited format.
% Delimiter is '\t'.
% Missing values are written as 'NaN'.
% We use a convention of prepending either C: or N: as one way to
% the variable name to distinguish categorical from numeric. 
%
% 'f' must have fields:
% data - Numeric data matrix, rows are items, columns are variables.
%        Missing values as NaN.
% head - Names of variables as a cell array.
% catI - Index set of categorical variables
% name - Any kind of an id string, written in the file if generateSampleHeader==1
%
% if transpose==0, writes items as rows, variables as columns.
%        In this shape categoricals are written as strings, 
%        prepending 'L' to the integer denoting  the level 
%        index [1..numLevels] of the categorical variable.
% Warning: this option is rather slow!
%
% if transpose==1, writes variables as rows, items as columns.
%        Values of categoricals are written as integers, without the
%        prepended 'L' (this allows fast vectorized writing that works with 
%        NaNs not producing 'LNaN' for the missing values!)
% 
% if generateSampleHeader==1, generates a sample header row/column.
%

separator = '\t';
[r,c] = size(f.data);
if r<1 || c<1, return; end % don't write a file with zero items or columns

if nargin<=2
	transpose=0;
end
if nargin<=3
	generateSampleHeader=0;
end

fd = fopen(name,'w');
categorical=zeros(1,c); categorical(f.catI)=1;

if transpose==0,  
    % Write rows as items, columns as features
    
    % header row
    if generateSampleHeader==1,
        fprintf(fd,['%s' separator],f.name);
    end
    for myCol=1:length(f.head),
		if categorical(myCol)==1,
			fprintf(fd, 'C:%s', f.head{myCol});
		else
			fprintf(fd, 'N:%s', f.head{myCol});
		end
		if myCol<length(f.head),
			fprintf(fd,separator);
		end
    end
    fprintf(fd,'\n');
    
% TODO Vectorized write using fprintf works except missing categoricals 
% TODO will be written as 'LNaN'   
%     % generate a row format string for the data
%     frmt = '';
%     if generateSampleHeader==1, frmt=[frmt 'S%d' separator]; end
%     for myCol=1:c,
%         if categorical(myCol)==0, frmt=[frmt '%g']; else frmt=[frmt 'L%d']; end
%         if myCol<c, frmt=[frmt separator]; end;
%     end
%     frmt=[frmt '\n'];
%     % fprintf writes data in column order, need to transpose to write in row order
%     if generateSampleHeader==1,
%         dataW = [1:r; f.data'];
%     else
%         dataW = f.data';
%     end
%     fprintf(fd, frmt, dataW);
%     clear dataW;
    
    % write data using multiple fprintf's (slow :(
    for myRow=1:r,
        if generateSampleHeader==1,
            fprintf(fd,['S%d' separator], myRow);
        end       
        for myCol=1:c,
           if myCol==c, sep='\n'; else sep=separator; end
           if isnan( f.data(myRow,myCol) ),
               fprintf(fd,['NaN' sep]);
           else
               if categorical(myCol)==0, frmt='%g'; else frmt='L%d'; end
               fprintf(fd,[frmt sep], f.data(myRow,myCol));
           end
        end
    end

else % transpose==1
    
    % Write rows as features, columns as items
    
    % sample names header
    if generateSampleHeader==1,
        fprintf(fd,'%s',f.name);
        for i=1:r,
            fprintf(fd,'\tS%d',i);
        end
        fprintf(fd,'\n');
    end
    
    % generate two format strings
    frmtN = separator; % because we continue after the header
    for i=1:r,
        frmtN = [frmtN '%f'];
        if i<r, frmtN = [frmtN separator]; end
    end
    frmtN = [frmtN '\n'];
    frmtC = separator;
    for i=1:r,
        frmtC = [frmtC '%d'];
        if i<r, frmtC = [frmtC separator]; end
    end
    frmtC = [frmtC '\n']; 
    
    % write each column in original data matrix as a row in file
    for myCol=1:c,         
        if categorical(myCol)==1, 
            fprintf(fd,'C:%s', f.head{myCol} );
            fprintf(fd,frmtC, f.data(:,myCol) );
        else % numerical
            fprintf(fd,'N:%s', f.head{myCol} );
            fprintf(fd,frmtN, f.data(:,myCol) );
        end
    end
    
end
fclose(fd);


%%
function dWriteArff(f, filename)

% function dWriteArff(f, filename)
%
% Saves the data structure in 'f' into file 'filename' in arff format. 
%
% 'f' must have fields:
% data - Numeric data matrix, rows are items, columns are variables.
%        Missing values as NaN.
% head - Names of variables as a cell array.
%
% 'f' may have fields:
% name - Any kind of an id string, written in the arff file
% catI - Index set of categorical variables
% catLevels - Numbers of levels of the categorical variables
% uniquesForCategorical - Specifies how many unique values a variable must
%   have in order to interpret it as a numerical (as opposed to categorical
%   variable) in the case the index set of categorical variables has not been 
%   explicitly given (default is > 32)
%
% Missing values are written as 'NaN'.

[r,c]=size(f.data);
if r<1 || c<1, return; end % don't write a file with zero items or columns
fid=fopen(filename,'w');
if isfield(f,'name'),
    fprintf(fid,'@relation %s\n',f.name);
else
    fprintf(fid,'@relation GeneratedData\n'); %default
end


categorical  = zeros(1,c);
numCatLevels = zeros(1,c);
if isfield(f,'catI'),
    categorical( f.catI ) = 1;
    if isfield(f,'catLevels'), 
        numCatLevels( f.catI ) = f.catLevels;
    end;
end

% print out attribute descriptions
for i=1:c,
    fprintf(fid,'\n@attribute %s ',f.head{i});
    
    % do we not have info about categoricals?
    if ~isfield(f,'catI'),
        % if not, count uniques
        uniqueValues = unique(f.data(:,i));
        if ~isfield(f,'uniquesForCategorical'),
            f.uniquesForCategorical = 32; %default
        end
        if length(uniqueValues) <= f.uniquesForCategorical,
            categorical(i) = 1;
        end
    else
        % if yes, then if categorical...
        if categorical(i)==1,
            % did we have information about the number of levels?
            if isfield(f,'catLevels'),
                % use it
                uniqueValues = 1:numCatLevels(i);
            else
                % otherwise enumerate uniques
                uniqueValues = unique(f.data(:,i));
            end
        end
    end
    
    if categorical(i)==0, %  real
        fprintf(fid,'real');
    else
        % categorical
        fprintf(fid,'{%d',uniqueValues(1) );
        for j=2:length(uniqueValues),
            fprintf(fid,',%d',uniqueValues(j));
        end
        fprintf(fid,'}');
    end
end

% print out data matrix comma separated
fprintf(fid,'\n\n@data\n');
% create a format string for a row in the array
frmt = '';
for i=1:c,
    if categorical(i)==0, frmt=[frmt '%g']; else frmt=[frmt '%d']; end
    if i<c, frmt=[frmt ',']; end;
end
frmt=[frmt '\n'];
% write using vectorized fwrite (column order - need transpose)
fprintf(fid, frmt, f.data');
fclose(fid);



