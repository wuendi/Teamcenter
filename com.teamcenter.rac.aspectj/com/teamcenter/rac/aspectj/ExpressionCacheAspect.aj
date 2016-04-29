// @<COPYRIGHT>@
// ==================================================
// Copyright 2015.
// Siemens Product Lifecycle Management Software Inc.
// All Rights Reserved.
// ==================================================
// @<COPYRIGHT>@

package com.teamcenter.rac.aspectj;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;

import org.apache.log4j.Logger;
import org.eclipse.core.expressions.EvaluationResult;
import org.eclipse.core.expressions.Expression;
import org.eclipse.core.expressions.ExpressionConverter;
import org.eclipse.core.expressions.ExpressionInfo;
import org.eclipse.core.expressions.IEvaluationContext;
import org.eclipse.core.internal.expressions.InstanceofExpression;
import org.eclipse.core.internal.expressions.IterateExpression;
import org.eclipse.core.internal.expressions.TestExpression;
import org.eclipse.core.runtime.CoreException;
import org.eclipse.core.runtime.IConfigurationElement;
import org.eclipse.ui.ISources;

/**
 * This aspect fixes a performance problem in the Eclipse mechanism which is
 * responsible for evaluating the visibleWhen and activeWhen etc expressions
 * defined in plugin.xml files that control the state of menu items, commands or
 * handlers. It implements a caching mechanism that prevents that the same
 * expressions are evaluated multiple times. <br>
 * <br>
 * As of 3.8 eclipse already contains a mechanism to identify identical
 * expressions and to cache the evaluation results, unfortunately this is done
 * only for top-level expressions. Since most expressions are compound
 * expressions which only differ slightly in details, the common sub expressions
 * will be evaluated multiple times. This is especially cumbersome in case a sub
 * expression requires some costly computation, like in the case of an iterate
 * expression that works on the selection. If the number of selected components
 * is huge (~ 5000), the expression evaluation will block the main thread for
 * several seconds and cause the UI to appear frozen. <br>
 * <br>
 * The approach used here is to identify sub expressions which appear multiple
 * times in different top-level expressions. All identical expressions are
 * replaced by one single expression instance of the new expression type
 * {@link ExpressionCacheAspect.ExpressionWrapper} . ExpressionWrapper will only
 * compute the expression if the value is not yet cached. The aspect identifies
 * the variable names a cached expression depends on and makes sure that the
 * cached value is cleared if the respective variable has been changed.
 */
@SuppressWarnings("restriction")
public privileged aspect ExpressionCacheAspect 
{
    static Logger logger = Logger.getLogger( ExpressionCacheAspect.class );

    /**
     * System property constant
     */
    private final static String systemProperty = "expressioncache.enable";

    /**
     * Check eclipse expression is cached by this aspect or not
     * 
     * @return boolean true eclipse expression is cached, false otherwise
     */
    public static boolean isPatchEnabled()
    {
        return "Y".equals(System.getProperty(systemProperty, "N"));
    }

    /**
     * Wrapper around expressions that holds the cached value of a previous
     * evaluation; the implementation requires that the {@link #clearResult()}
     * method is invoked in case any variable that affects the outcome of the
     * wrapped expression changes
     */
    private static class ExpressionWrapper extends Expression
    {
        /** original expression created by the eclipse framework */
        private final Expression wrappedExpression;

        /** cached result of previous expression evaluation */
        private EvaluationResult evaluationResult = null;

        /** set to true to enable caching for this particular expression; the value is determined from the expression info */
        private boolean cacheResult = false;

        /** set to true that the expression info has already been evaluated */
        private boolean expressionInfoIsEvaluated = false;

        /**
         * Map that lists all cached expressions which depend on a particular
         * variable name.
         */
        static Map<String, List<ExpressionWrapper>> cacheDependencyMap = new HashMap<String, List<ExpressionWrapper>>();

        /**
         * Constructor
         * 
         * @param expr Expression
         */
        public ExpressionWrapper(Expression expr)
        {
            this.wrappedExpression = expr;
        }

        @Override
        public void collectExpressionInfo(ExpressionInfo info)
        {
            wrappedExpression.collectExpressionInfo(info);
        }

        @Override
        public int hashCode()
        {
            return wrappedExpression.hashCode();
        }

        /**
         * Evaluation
         * 
         * @param context
         * @return
         * @throws CoreException
         */
        @Override
        public EvaluationResult evaluate(IEvaluationContext context)
               throws CoreException
        {
            if (evaluationResult == null || !cacheResult)
            {
                //Don't remove it. This is for testing.
            	//long startTime = System.nanoTime();

                evaluationResult = wrappedExpression.evaluate(context);

                // Use the expression info to determine whether we are allowed to cache the expression
                // result (cacheResult == true);
                // note that the expression info might not be available when the expression was created, so
                // we have to wait until the expression is first evaluated to be able to process it
                if (evaluationResult != EvaluationResult.NOT_LOADED)
                {
                    if (!expressionInfoIsEvaluated)
                    {
                        evaluateExpressionInfo();

                        expressionInfoIsEvaluated = true;
                    }
                }

                //long delta = System.nanoTime() - startTime;
                //final long factor = 1000000;

                //if (delta > 100 * factor)
                //{
                //    logger.info("Evaluation of " + this.toString()
                //            + " took " + delta / (double) factor
                //            + " msec");
                //}
            }

            return evaluationResult;
        }

        /**
         * Evaluation Expression Info; updates the cacheResult variable and
         * register the expression to be a dependent of the set of variables
         * it evaluates 
         */
        private void evaluateExpressionInfo()
        {
            ExpressionInfo info = new ExpressionInfo();
            collectExpressionInfo(info);

            // only cache expressions that are not depending on the context
            // defined by outer expressions
            cacheResult = !info.hasDefaultVariableAccess();

            // a special case is the iterate expressions depends on selection,
            // but lower level iterate expressions depends on context, so they
            // should not be cached (!!!)
            if (wrappedExpression instanceof IterateExpression)
            {
                cacheResult = true;
            }

            if (cacheResult)
            {
                // make sure that the cached value is cleared if any of the
                // variables changes the expression is depending on

                for (String name : getDependencyNames(info))
                {
                    List<ExpressionWrapper> dependentExpressions = cacheDependencyMap
                            .get(name);

                    if (dependentExpressions == null)
                    {
                        dependentExpressions = new ArrayList<ExpressionWrapper>();
                        cacheDependencyMap.put(name, dependentExpressions);
                    }

                    dependentExpressions.add(this);
                }
            }
        }

        /**
         * Get dependency names
         * @param info
         * @return
         */
        private static String[] getDependencyNames(ExpressionInfo info)
        {
            List<String> names = new ArrayList<String>(Arrays.asList(info
                    .getAccessedVariableNames()));

            if (info.hasDefaultVariableAccess())
            {
                names.add(ISources.ACTIVE_CURRENT_SELECTION_NAME);
            }

            names.addAll(Arrays.asList(info.getAccessedPropertyNames()));

            return names.toArray(new String[names.size()]);
        }

        /**
         * Clear the cached evaluation result for this particular expression.
         */
        public void clearResult()
        {
            evaluationResult = null;
        }

        /**
         * Clear the cached results for all expressions that depend on the specified set of variables.
         * 
         * @param names
         */
        public static void clearCachedResults(String[] names)
        {
            for (String name : names)
            {
                List<ExpressionWrapper> dependentExpressions = cacheDependencyMap
                        .get(name);

                if (dependentExpressions != null)
                {
                    for (ExpressionWrapper cache : dependentExpressions)
                    {
                        cache.clearResult();
                    }
                }
            }
        }

        /**
         * Get configuration element definition
         * 
         * @param configurationElement
         * @return
         */
        public static String getConfigurationElementDefinition(IConfigurationElement configurationElement)
        {
            StringBuilder sb = new StringBuilder();

            String contributor = configurationElement.getContributor()
                   .getName();
            sb.append(contributor);

            List<String> components = new ArrayList<String>();

            Object element = configurationElement;
            while (element instanceof IConfigurationElement)
            {
                IConfigurationElement cElem = (IConfigurationElement) element;

                String component = cElem.getName();

                String id = cElem.getAttribute("class");
                if (id == null)
                {
                    id = cElem.getAttribute("commandId");

                    if (id == null)
                    {
                        id = cElem.getAttribute("id");
                    }
                }

                if (id != null)
                {
                    component += "[" + id + "]";
                }
                components.add(component);

                element = cElem.getParent();
            }

            for (int i = components.size(); i-- > 0;)
            {
                sb.append("/");
                sb.append(components.get(i));
            }

            return sb.toString();
        }

        /**
         * Verbose description of all the extensions that use this expression;
         * available for top-level expressions only.
         */
        private ArrayList<String> extensions;

        /**
         * Parse the XML definition of the configuration element to get a meaningful description of the associated extension.
         * 
         * @param configurationElement
         */
        public void addReferencingExtension(
                IConfigurationElement configurationElement)
        {
            String definition = getConfigurationElementDefinition(configurationElement);

            if (extensions == null)
            {
                extensions = new ArrayList<String>();
            }

            extensions.add(definition);
        }

        @Override
        public String toString()
        {
            Expression expr = wrappedExpression;

            StringBuilder sb = new StringBuilder();

            if (expr instanceof TestExpression || expr instanceof InstanceofExpression)
                sb.append(expr.toString());
            else
                sb.append(expr.getClass().getSimpleName());

            if (extensions != null)
            {
                sb.append(" used by ");

                int cnt = 0;
                for (String s : extensions)
                {
                    if (cnt++ != 0)
                    {
                        sb.append(", ");
                    }
                    sb.append(s);
                }
            }

            return sb.toString();
        }
    }

    /**
     * Map that holds for each expression the cached representation; note that
     * the map depends on the overloaded
     * {@link org.eclipse.core.expressions.Expression#equals()} and
     * {@link org.eclipse.core.expressions.Expression#hashCode()} methods which
     * make sure that different expressions that check the exact same conditions
     * are mapped to the same instance of
     * {@link ExpressionCacheAspect.ExpressionWrapper}.
     */
    Map<Expression, ExpressionWrapper> expressionWrappers = new HashMap<Expression, ExpressionWrapper>();

    /**
     * Point cut to hook into
     * {@link org.eclipse.core.internal.expressions.StandardElementHandler#create}
     * . This is the central function where all expressions which are defined in
     * a plugin.xml are created.
     * 
     * @param converter
     *            don't care, only used for binding the second argument
     * @param configurationElement
     *            a representation of the XML representation of the expression
     */
    pointcut expressionCreation(ExpressionConverter converter,
             IConfigurationElement configurationElement) :  
        execution(Expression org.eclipse.core.internal.expressions.StandardElementHandler.create(ExpressionConverter, IConfigurationElement)) &&
        args(converter, configurationElement);

    int expressionCreationLevel;
    boolean enableWrapperGeneration;

    static HashSet<String> interceptedExtensionPoints;
    static HashSet<String> interceptedDefintionContributors;

    // [PR 7621483]
    // to prevent interfering with applications that use the eclipse expression framework for other purposes than evaluating the 
    // state or availability of a UI command, we now only intercept the expression evaluation in that context;
    // particularly problematic is the fact that in ExpressionWrapper.getDependencyNames(ExpressionInfo) we link an expression
    // that accesses its context value to the selection; this will most likely not be true when the expression is used for other
    // purposes
    private boolean okToInterceptExpressionCreation(
            IConfigurationElement configurationElement)
    {
        String extensionPoint = configurationElement.getDeclaringExtension().getExtensionPointUniqueIdentifier();

        if (interceptedExtensionPoints.contains(extensionPoint))
            return true;

        if (extensionPoint.equals("org.eclipse.core.expressions.definitions"))
        {
            String contributor = configurationElement.getContributor().getName();

            if (interceptedDefintionContributors.contains(contributor))
                return true;
        }

        return false;
    }

    static
    {
        interceptedExtensionPoints = new HashSet<String>();

        interceptedExtensionPoints.add("org.eclipse.ui.menus");
        interceptedExtensionPoints.add("org.eclipse.ui.handlers");
        interceptedExtensionPoints.add("org.eclipse.ui.activities");

        interceptedExtensionPoints.add("com.teamcenter.rac.cme.framework.toolbarToggleButtons");
        interceptedExtensionPoints.add("com.teamcenter.rac.cme.framework.toolbarMenu");

        interceptedDefintionContributors = new HashSet<String>();

        interceptedDefintionContributors.add("com.teamcenter.rac.cme.mpp");
        interceptedDefintionContributors.add("com.teamcenter.rac.cme.pmp");
        interceptedDefintionContributors.add("com.teamcenter.rac.cme.bvr.connect");
        interceptedDefintionContributors.add("com.teamcenter.rac.cme.ccadmin");
        interceptedDefintionContributors.add("com.teamcenter.rac.pse");
        interceptedDefintionContributors.add("com.teamcenter.bce.editor");      
        interceptedDefintionContributors.add("com.teamcenter.rac.ui");      
        interceptedDefintionContributors.add("com.teamcenter.rac.ui.advanced");     

        interceptedDefintionContributors.add("com.teamcenter.rac.accessmanager");
        interceptedDefintionContributors.add("com.teamcenter.rac.adalicense");
        interceptedDefintionContributors.add("com.teamcenter.rac.aif.registryeditor");
        interceptedDefintionContributors.add("com.teamcenter.rac.aifrcp");
        interceptedDefintionContributors.add("com.teamcenter.rac.architecturemodeler");
        interceptedDefintionContributors.add("com.teamcenter.rac.auditmanager");
        interceptedDefintionContributors.add("com.teamcenter.rac.authorization");
        interceptedDefintionContributors.add("com.teamcenter.rac.caese");
        interceptedDefintionContributors.add("com.teamcenter.rac.classification.icadmin");
        interceptedDefintionContributors.add("com.teamcenter.rac.classification.icm");
        interceptedDefintionContributors.add("com.teamcenter.rac.cm");
        interceptedDefintionContributors.add("com.teamcenter.rac.cme.activity");
        interceptedDefintionContributors.add("com.teamcenter.rac.cme.biw.module");
        interceptedDefintionContributors.add("com.teamcenter.rac.cme.cmereport");
        interceptedDefintionContributors.add("com.teamcenter.rac.cme.collaborationcontext");
        interceptedDefintionContributors.add("com.teamcenter.rac.cme.ebop.module");
        interceptedDefintionContributors.add("com.teamcenter.rac.cme.fse");
        interceptedDefintionContributors.add("com.teamcenter.rac.cme.lb");
        interceptedDefintionContributors.add("com.teamcenter.rac.cme.legacy");
        interceptedDefintionContributors.add("com.teamcenter.rac.cme.mrm");
        interceptedDefintionContributors.add("com.teamcenter.rac.cme.pad");
        interceptedDefintionContributors.add("com.teamcenter.rac.cme.sequence");
        interceptedDefintionContributors.add("com.teamcenter.rac.cme.variants");
        interceptedDefintionContributors.add("com.teamcenter.rac.commands.report.reportdesigner");
        interceptedDefintionContributors.add("com.teamcenter.rac.commandsuppression");
        interceptedDefintionContributors.add("com.teamcenter.rac.common");
        interceptedDefintionContributors.add("com.teamcenter.rac.contmgmtbase");
        interceptedDefintionContributors.add("com.teamcenter.rac.crf");
        interceptedDefintionContributors.add("com.teamcenter.rac.databaseutilities");
        interceptedDefintionContributors.add("com.teamcenter.rac.datadic");
        interceptedDefintionContributors.add("com.teamcenter.rac.designcontext");
        interceptedDefintionContributors.add("com.teamcenter.rac.ecmanagement");
        interceptedDefintionContributors.add("com.teamcenter.rac.gantt");
        interceptedDefintionContributors.add("com.teamcenter.rac.issuemanager");
        interceptedDefintionContributors.add("com.teamcenter.rac.multistructures");
        interceptedDefintionContributors.add("com.teamcenter.rac.organization");
        interceptedDefintionContributors.add("com.teamcenter.rac.plmxmlexportimportadministration");
        interceptedDefintionContributors.add("com.teamcenter.rac.project");
        interceptedDefintionContributors.add("com.teamcenter.rac.querybuilder");
        interceptedDefintionContributors.add("com.teamcenter.rac.requirementsmanager");
        interceptedDefintionContributors.add("com.teamcenter.rac.schedule");
        interceptedDefintionContributors.add("com.teamcenter.rac.smb");
        interceptedDefintionContributors.add("com.teamcenter.rac.subscriptionmonitor");
        interceptedDefintionContributors.add("com.teamcenter.rac.tcgrb");
        interceptedDefintionContributors.add("com.teamcenter.rac.tcsim");
        interceptedDefintionContributors.add("com.teamcenter.rac.tcsim.analysis");
        interceptedDefintionContributors.add("com.teamcenter.rac.tcsim.composite");
        interceptedDefintionContributors.add("com.teamcenter.rac.tcsim.datamonitor");
        interceptedDefintionContributors.add("com.teamcenter.rac.tcsim.derivativerules");
        interceptedDefintionContributors.add("com.teamcenter.rac.tcsim.inspector");
        interceptedDefintionContributors.add("com.teamcenter.rac.tcsim.model");
        interceptedDefintionContributors.add("com.teamcenter.rac.tcsim.toolmanagement");
        interceptedDefintionContributors.add("com.teamcenter.rac.validation");
        interceptedDefintionContributors.add("com.teamcenter.rac.vis");
        interceptedDefintionContributors.add("com.teamcenter.rac.workflow.processdesigner");
        interceptedDefintionContributors.add("com.teamcenter.rac.workflow.processviewer");
    }

    /**
     * Wrap around the framework function that creates expressions from its XML representation.
     * 
     * @param converter
     *         don't care
     * @param configurationElement
     *         the XML representation; only needed for debugging purposes
     * @return a common Expression instance for all configuration elements with
     *         the same definition
     */
    Expression around(ExpressionConverter converter,
        IConfigurationElement configurationElement) : expressionCreation(converter, configurationElement)
    {
    	if ( !isPatchEnabled() )
    	{
            return proceed(converter, configurationElement);
    	}

    	boolean resetWrapperGenerationFlag = false;

    	// check whether to create wrappers for an expression tree 
    	// if expression level is 0 we are at the top of the tree directly below the enableWhen etc. clause
        if (expressionCreationLevel == 0)
        {
            if ( okToInterceptExpressionCreation(configurationElement))
            {
                resetWrapperGenerationFlag = enableWrapperGeneration = true;
            }

            // In case of performance problems when selecting a large set of options, re-enable the following code
            // unfortunately the output cannot be controlled by the logger framework since using the Logger class
            // at this point will cause a class loader exception
            // else
            // {
            //     String extensionPoint = configurationElement.getDeclaringExtension().getExtensionPointUniqueIdentifier();
            //     System.out.println(
            //     "HUGO: " + extensionPoint + ": " + ExpressionWrapper.getConfigurationElementDefinition(configurationElement) + " not intercepted");
            // }
        }

        boolean createWrapper = (enableWrapperGeneration == true);
        expressionCreationLevel++;

        Expression resultExpression;
        try
        {
            // this will create first the sub expressions and then add them to the expression created by the configuration element 
            resultExpression = proceed(converter, configurationElement);
        }
        finally
        {
            expressionCreationLevel--;

            if (resetWrapperGenerationFlag)
            {
                enableWrapperGeneration = false;
            }
        }

        if (createWrapper)
        {
            ExpressionWrapper wrapper = expressionWrappers.get(resultExpression);

            // if no cached expression is defined that represents the same
            // condition, create one
            if (wrapper == null)
            {
                wrapper = new ExpressionWrapper(resultExpression);
                expressionWrappers.put(resultExpression, wrapper);
            }

            // for top-level expressions we collect the referencing extensions 
            if (expressionCreationLevel == 0)
            {
                // let the wrapper of the top-level expression know which
                // extensions use the expression so that we can identify
                // expressions that are implemented inefficiently
                wrapper.addReferencingExtension(configurationElement);
            }

            return wrapper;
        }

        return resultExpression;
    }

    /**
     * Point cut to hook into {@link
     * org.eclipse.ui.internal.services.EvaluationAuthority.startSourceChange(
     * String[])}. This function is invoked before the expressions are
     * reevaluated because a variable that may or may not affect the result of
     * the registered expressions has changed.
     * 
     * @param names
     *     the names of the variables that have changed
     */
    pointcut startSourceChange(String[] names) :
        execution(void org.eclipse.ui.internal.services.EvaluationAuthority.startSourceChange(String[])) &&
        args(names);

    long startTime = 0;

    before(String[] names) : startSourceChange(names)
    {
        if ( isPatchEnabled() )
        {
            if ( logger.isDebugEnabled() )
            {
                if (startTime == 0)
                {
                    startTime = System.nanoTime();
                }
            }
            ExpressionWrapper.clearCachedResults(names);
        }
    }

    pointcut endSourceChange() :
        execution(void org.eclipse.ui.internal.services.EvaluationAuthority.endSourceChange(String[]));

    after() : endSourceChange()
    {
        if ( isPatchEnabled() && logger.isDebugEnabled() )
        {
            long delta = System.nanoTime() - startTime;
            final long factor = 1000000;

            if (delta > 100 * factor)
            {
                logger.debug("-- end of source change, elapsed time = " + delta
                    / (double) factor + " msec");
            }
            startTime = 0;
        }
    }
}
