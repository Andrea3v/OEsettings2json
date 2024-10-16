 % converts settings.xml file gen by Open Ephys during recordings to channel map for Kilosort
 % chan map is saved as .json and .mat 

[File,Path] = uigetfile({'*.xml'},'select OE settings.xml file','D:\channelmaps');
[~, name0,~] = fileparts(File);
name0       = extractAfter(name0,'settings'); % grab
OEinfo      = xml2struct(fullfile(Path,File));

% xml parserer to structure won't retain the order of the channels as in the xml, making the wrong channel map > use
% raw text reader instead

xmlText = fileread(fullfile(Path,File));
expr = '<(?<type>[!?/]?)(?<name>[\w:.-]+)(?<attributes>[^>]*)>(?<content>[^<]*)';
tokens  = regexp(xmlText, expr, 'names');
indxChn = contains({tokens.name},'CHANNELS','IgnoreCase',false);
allChnsTxt = tokens(indxChn).attributes;
chNumbers = regexp(allChnsTxt, 'CH(\d+)','tokens');
chNumbers = str2double([chNumbers{:}]);                                     % actual channel order
shankNum = regexp(allChnsTxt, ':(\d+)', 'tokens');
shankNum = str2double([shankNum{:}]);                                       % Convert from cell array to numeric vector

probeinfo   = OEinfo.SETTINGS.SIGNALCHAIN.PROCESSOR{1,1}.EDITOR;
if ~contains(probeinfo.Attributes.displayName,'Neuropix-PXI')
    error('probe info does not contain "Neuropix-PXI", but %s?',probeinfo.Attributes.displayName)
end

% fs

fs0     = OEinfo.SETTINGS.SIGNALCHAIN.PROCESSOR{1,1}.STREAM.Attributes.sample_rate; 
fs      = str2double(fs0);
% grab xc,yx,kc

chans   = probeinfo.NP_PROBE.CHANNELS.Attributes;
xc      = probeinfo.NP_PROBE.ELECTRODE_XPOS.Attributes;
yc      = probeinfo.NP_PROBE.ELECTRODE_YPOS.Attributes;

chnsC   = fieldnames(chans);
chnsX   = fieldnames(xc);
chnsY   = fieldnames(yc);
if isequal(chnsC,chnsX) && isequal(chnsC,chnsY)

    chns        = cellfun(@(x) strrep(x, 'CH', ''), chnsC, 'UniformOutput', false);
    chMap0ind   = str2double(chns);
    
    if ~numel(chNumbers) == numel(chMap0ind)
        error('number of channel mismatch %d vs %d, check settings.xml file',numel(chNumbers),numel(chMap0ind))
    else

        sortedChns = zeros(size(chNumbers));
        for i = 1:length(chNumbers)
            sortedChns(i) = find(chMap0ind == chNumbers(i));
        end
    end

    xcoords     = nan(numel(chMap0ind),1);
    for c1 = 1:numel(chnsC)
        xcoords(c1,1) = str2double(xc.(chnsC{c1}));
    end
    xcoords = xcoords(sortedChns);

    ycoords     = nan(numel(chMap0ind),1);
    for c2 = 1:numel(chnsC)
        ycoords(c2,1) = str2double(yc.(chnsC{c2}));
    end
    
    ycoords = ycoords(sortedChns);

    cmap        = winter(numel(chMap0ind));
    f1          = figure('Name','Probe','Color','w','NumberTitle','off','Position',[295 50 649 946],'Renderer','painters'); 
    scatter(xcoords,ycoords,50,cmap,'s', 'filled');
    axis('equal')
    allxpos     = sort(unique(xcoords));
    
    groups      = [allxpos,zeros(size(allxpos))];  % Start all in group 0
    groupN      = 0;

    for i = 2:length(allxpos)
        if allxpos(i) - allxpos(i-1) > 200 % if site is >0.2mm then it's a different group
            groupN      = groupN + 1;
        end
        groups(i,2)     = groupN;
    end

    kcoords     = nan(numel(xcoords),1);
    for k = 1:numel(allxpos)
        indx        = xcoords == groups(k,1);
        kcoords(indx) = groups(k,2);
    end
    
    % SAVE  .json
    chanMapStruct = struct('chanMap',chMap0ind,'xc',xcoords,'yc',ycoords,'kcoords',kcoords,'n_chan',numel(chMap0ind));
    jsonChanMap = jsonencode(chanMapStruct);
    name        = 'KS_chanMap'; 
    jsonName    = fullfile(Path, [name, name0, '.json']);
    fileID      = fopen(jsonName, 'w');
    fprintf(fileID, '%s', jsonChanMap);
    fclose(fileID);
    
    % SAVE .mat
    chMap       = chMap0ind+1;
    connected   = true(numel(chMap0ind),1); 
    save(fullfile(Path, [name name0 '.mat']), ...
    'chMap', 'connected', 'xcoords', 'ycoords', 'kcoords', 'chMap0ind', 'name', 'fs')

    % SAVE figure
    
    saveas(f1,fullfile(Path, [name, name0, '_probeView.fig']))

else
    error('non-matching channels in x,y coordinates, check settings.xml file')
end


% old function xml2struct
function [ s ] = xml2struct( file )
%Convert xml file into a MATLAB structure
% [ s ] = xml2struct( file )
%
% A file containing:
% <XMLname attrib1="Some value">
%   <Element>Some text</Element>
%   <DifferentElement attrib2="2">Some more text</Element>
%   <DifferentElement attrib3="2" attrib4="1">Even more text</DifferentElement>
% </XMLname>
%
% Will produce:
% s.XMLname.Attributes.attrib1 = "Some value";
% s.XMLname.Element.Text = "Some text";
% s.XMLname.DifferentElement{1}.Attributes.attrib2 = "2";
% s.XMLname.DifferentElement{1}.Text = "Some more text";
% s.XMLname.DifferentElement{2}.Attributes.attrib3 = "2";
% s.XMLname.DifferentElement{2}.Attributes.attrib4 = "1";
% s.XMLname.DifferentElement{2}.Text = "Even more text";
%
% Please note that the following characters are substituted
% '-' by '_dash_', ':' by '_colon_' and '.' by '_dot_'
%
% Written by W. Falkena, ASTI, TUDelft, 21-08-2010
% Attribute parsing speed increased by 40% by A. Wanner, 14-6-2011
% Added CDATA support by I. Smirnov, 20-3-2012
%
% Modified by X. Mo, University of Wisconsin, 12-5-2012

    if (nargin < 1)
        clc;
        help xml2struct
        return
    end
    
    if isa(file, 'org.apache.xerces.dom.DeferredDocumentImpl') || isa(file, 'org.apache.xerces.dom.DeferredElementImpl')
        % input is a java xml object
        xDoc = file;
    else
        %check for existance
        if (exist(file,'file') == 0)
            %Perhaps the xml extension was omitted from the file name. Add the
            %extension and try again.
            if (isempty(strfind(file,'.xml')))
                file = [file '.xml'];
            end
            
            if (exist(file,'file') == 0)
                error(['The file ' file ' could not be found']);
            end
        end
        %read the xml file
        xDoc = xmlread(file);
    end
    
    %parse xDoc into a MATLAB structure
    s = parseChildNodes(xDoc);
    
end
% ----- Subfunction parseChildNodes -----
function [children,ptext,textflag] = parseChildNodes(theNode)
    % Recurse over node children.
    children = struct;
    ptext = struct; textflag = 'Text';
    if hasChildNodes(theNode)
        childNodes = getChildNodes(theNode);
        numChildNodes = getLength(childNodes);

        for count = 1:numChildNodes
            theChild = item(childNodes,count-1);
            [text,name,attr,childs,textflag] = getNodeData(theChild);
            
            if (~strcmp(name,'#text') && ~strcmp(name,'#comment') && ~strcmp(name,'#cdata_dash_section'))
                %XML allows the same elements to be defined multiple times,
                %put each in a different cell
                if (isfield(children,name))
                    if (~iscell(children.(name)))
                        %put existsing element into cell format
                        children.(name) = {children.(name)};
                    end
                    index = length(children.(name))+1;
                    %add new element
                    children.(name){index} = childs;
                    if(~isempty(fieldnames(text)))
                        children.(name){index} = text; 
                    end
                    if(~isempty(attr)) 
                        children.(name){index}.('Attributes') = attr; 
                    end
                else
                    %add previously unknown (new) element to the structure
                    children.(name) = childs;
                    if(~isempty(text) && ~isempty(fieldnames(text)))
                        children.(name) = text; 
                    end
                    if(~isempty(attr)) 
                        children.(name).('Attributes') = attr; 
                    end
                end
            else
                ptextflag = 'Text';
                if (strcmp(name, '#cdata_dash_section'))
                    ptextflag = 'CDATA';
                elseif (strcmp(name, '#comment'))
                    ptextflag = 'Comment';
                end
                
                %this is the text in an element (i.e., the parentNode) 
                if (~isempty(regexprep(text.(textflag),'[\s]*','')))
                    if (~isfield(ptext,ptextflag) || isempty(ptext.(ptextflag)))
                        ptext.(ptextflag) = text.(textflag);
                    else
                        %what to do when element data is as follows:
                        %<element>Text <!--Comment--> More text</element>
                        
                        %put the text in different cells:
                        % if (~iscell(ptext)) ptext = {ptext}; end
                        % ptext{length(ptext)+1} = text;
                        
                        %just append the text
                        ptext.(ptextflag) = [ptext.(ptextflag) text.(textflag)];
                    end
                end
            end
            
        end
    end
end
% ----- Subfunction getNodeData -----
function [text,name,attr,childs,textflag] = getNodeData(theNode)
    % Create structure of node info.
    
    %make sure name is allowed as structure name
    name = toCharArray(getNodeName(theNode))';
    name = strrep(name, '-', '_dash_');
    name = strrep(name, ':', '_colon_');
    name = strrep(name, '.', '_dot_');

    attr = parseAttributes(theNode);
    if (isempty(fieldnames(attr))) 
        attr = []; 
    end
    
    %parse child nodes
    [childs,text,textflag] = parseChildNodes(theNode);
    
    if (isempty(fieldnames(childs)) && isempty(fieldnames(text)))
        %get the data of any childless nodes
        % faster than if any(strcmp(methods(theNode), 'getData'))
        % no need to try-catch (?)
        % faster than text = char(getData(theNode));
        text.(textflag) = toCharArray(getTextContent(theNode))';
    end
    
end
% ----- Subfunction parseAttributes -----
function attributes = parseAttributes(theNode)
    % Create attributes structure.

    attributes = struct;
    if hasAttributes(theNode)
       theAttributes = getAttributes(theNode);
       numAttributes = getLength(theAttributes);

       for count = 1:numAttributes
            %attrib = item(theAttributes,count-1);
            %attr_name = regexprep(char(getName(attrib)),'[-:.]','_');
            %attributes.(attr_name) = char(getValue(attrib));

            %Suggestion of Adrian Wanner
            str = toCharArray(toString(item(theAttributes,count-1)))';
            k = strfind(str,'='); 
            attr_name = str(1:(k(1)-1));
            attr_name = strrep(attr_name, '-', '_dash_');
            attr_name = strrep(attr_name, ':', '_colon_');
            attr_name = strrep(attr_name, '.', '_dot_');
            attributes.(attr_name) = str((k(1)+2):(end-1));
       end
    end
end