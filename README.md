# Teamcenter aspectj open source
This project is fixing performance problem in Eclipse 3.8 core expression module evaluating the visibleWhen and activeWhen clause defined plugin.xml to control the state of menu command items, command handlers. It implements a caching mechanism preventing same expression iteration evalated multiple times. We are using aspectj compiler to weave eclipse 3.8 core expression API in org.eclipse.core.expression and org.eclipse.ui.workbench plugins, during runtime, eclipse APIs execute our point out code to get caching to improve the performance 

## Source code and binary
1. The source files are located in com.teamcenter.rac.aspectj package.

2. The binary plugins are located in binary directory, contains three plugins built by perl script.

3. The build script is patchrcp.pl

## Build
1. Download aspectj 1.7.2 compiler for weaving from
http://www.eclipse.org/downloads/download.php?file=/tools/aspectj/aspectj-1.7.2.jar 

2. Download aspectj eclipse runtime plugin to build com.teamcenter.rac.aspectj and runtime execution in rcp
http://download.eclipse.org/tools/ajdt/42/update/ajdt_2.2.1_for_eclipse_4.2.zip

3. Then execute patchrcp.pl to build com.teamcenter.rac.aspectj.jar, org.eclipse.core.expressions.jar and org.eclipse.ui.workbench.jar 

