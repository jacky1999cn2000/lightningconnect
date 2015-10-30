/*
	继承DataSource.Connection类：支持sync,query,和search
		sync - 允许Salesforce读取外部系统的表结构(schema)
		query - 支持SOQL查询，以及在Salesforce的list view或detail page中浏览外部数据
		search - 支持SOSL查询，以及支持Salesforce global search
*/
global class LoopbackDataSourceConnection extends DataSource.Connection{

		/*
			构造器
		*/
		global LoopbackDataSourceConnection(DataSource.ConnectionParams connectionParams) {}
		global LoopbackDataSourceConnection() {}

		/*
			在外部数据源界面中，当admin点击"Validate and Sync"按钮时被调用，返回外部数据源中可用的数据表
		*/
		override global List<DataSource.Table> sync(){
				List<DataSource.Table> tables = new List<DataSource.Table>();

				List<DataSource.Column> columns = new List<DataSource.Column>();

				//每一个外部数据表(external object)都要包含ExternalId和DisplayUrl两个字段
				columns.add(DataSource.Column.text('ExternalId', 255));
				columns.add(DataSource.Column.url('DisplayUrl'));
				columns.add(DataSource.Column.text('Name', 255));
				columns.add(DataSource.Column.text('Phone', 255));
				columns.add(DataSource.Column.number('NumberOfEmployees', 18, 0));

				//表名(external object name)，用来当external object name字段的字段名，以及所有字段(columns)
				tables.add(DataSource.Table.get('Looper', 'Name', columns));
				return tables;
		}

		/*
			对外部数据的每一次SOQL操作(包括直接的SOQL操作，以及UI交互时系统自动产生的SOQL操作)都会触发query函数，并传入DataSource.QueryContext参数
			DataSource.QueryContext参数含有queryMoreToken和tableSelection两个属性，这里主要用了后者
				tableSelection属性描述了SOQL语句的每一个层面，columnsSelected相对应于SELECT，filter相对应于WHERE,order相对应于ORDER，tableSelected相对应于FROM
				这里tableSelected是一个String，因为query基本上是针对某一个table来操作的

			filter(DataSource.Filter)需要额外注意，它包含columnName,columnValue,type,tableName,subfilters这几个属性
				type可以是简单属性或者复杂属性
					简单属性包括诸如 DataSource.FilterType.CONTAINS、DataSource.FilterType.EQUALS等
					复杂属性包括诸如 DataSource.FilterType.OR_、DataSource.FilterType.AND_等
				如果是简单属性的type，则subfilters为null，只需要 columnName type columnValue 来组合SOQL语句即可，比如 columnName = columnValue
				如果是复杂属性的type，则需要遍历其subfilters，然后递归组合出最后的SOQL语句
				具体见下面 getSoqlFilter() 和其他相关方法

			https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_class_DataSource_QueryContext.htm#apex_class_DataSource_QueryContext
		*/
		override global DataSource.TableResult query(DataSource.QueryContext context){

				System.debug('***DataSource.QueryContext: '+context);

				//目前的API对外部数据的aggregation仅支持 COUNT()，这个IF主要是来应付如下SOQL: SELECT COUNT() FROM EXTERNALOBJECT
				if(context.tableSelection.columnsSelected.size() == 1 && context.tableSelection.columnsSelected.get(0).aggregation == DataSource.QueryAggregation.COUNT){
						Integer count = execCount(getCountQuery(context.tableSelection.filter));
						List<Map<String, Object>> countResponse = new List<Map<String, Object>>();
						Map<String, Object> countRow = new Map<String, Object>();
						countRow.put(context.tableSelection.columnsSelected.get(0).columnName, count);
						countResponse.add(countRow);
						return DataSource.TableResult.get(context, countResponse);
				}else{
						List<Map<String, Object>> rows = execQuery(getSoqlQuery(context.tableSelection.filter));
						return DataSource.TableResult.get(context, rows);
				}
		}

		/*
			对外部数据的每一次SOSL操作(主要是全局搜索)都会触发search函数，并传入DataSource.SearchContext参数

			DataSource.SearchContext参数有两个属性，searchPhrase和tableSelections
			searchPhrase不言自明，注意tableSelections - 是复数 - 数据类型是List<DataSource.TableSelection>
			当你的外部数据源里包含多个表时，需要处理每一个表的search(这个例子只包含了一个表)

			所谓的search，其实就是决定哪些字段去匹配searchPhrase的问题
			比如如果用Salesforce提供的 DataSource.SearchUtils.searchByName()方法的话，则仅仅会用Name字段来匹配searchPhrase
			(e.g. SELECT ... FROM ... WHERE Name LIKE '%searchPhrase%)

			这个例子自定义了search方法，用Name和Phone两个字段来匹配searchPhrase

			https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_class_DataSource_SearchContext.htm#apex_class_DataSource_SearchContext
		*/
		override global List<DataSource.TableResult> search(DataSource.SearchContext context){
				System.debug('***DataSource.SearchContext: '+context);

				// 不使用Salesforce提供的方法
				//return DataSource.SearchUtils.searchByName(context, this);

				List<DataSource.TableResult> results =new List<DataSource.TableResult>();

				//自定义的search本质上还是做SOQL query，我们自定义了一个含有两个subfilters，type为OR_的filter
				//这样在全局搜索的时候，Name或者Phone两个字段，只有有一个满足searchPhrase，该record就会被返回
				List<DataSource.Filter> subfilters = new List<Datasource.Filter>();

				DataSource.Filter subfilter1 = new DataSource.Filter();
				subfilter1.columnName = 'Name';
				subfilter1.columnValue = context.searchPhrase;
				subfilter1.subfilters = null;
				subfilter1.tableName = 'Looper';
				subfilter1.type = DataSource.FilterType.CONTAINS;

				DataSource.Filter subfilter2 = new DataSource.Filter();
				subfilter2.columnName = 'Phone';
				subfilter2.columnValue = context.searchPhrase;
				subfilter2.subfilters = null;
				subfilter2.tableName = 'Looper';
				subfilter2.type = DataSource.FilterType.CONTAINS;

				subfilters.add(subfilter1);
				subfilters.add(subfilter2);

				DataSource.Filter filter = new DataSource.Filter();
				filter.columnName = null;
				filter.columnValue = null;
				filter.subfilters = subfilters;
				filter.tableName = 'Looper';
				filter.type = DataSource.FilterType.OR_;

				List<Map<String, Object>> rows = execQuery(getSearchQuery(filter));
				results.add(DataSource.TableResult.get(true, null, 'Looper', rows));
        return results;
		}

		/*
			用来执行SOQL，并为最后的外部数据表最适合的数据转换(比如ExternalId和DisplayUrl)
		*/
		private List<Map<String, Object>> execQuery(String soqlQuery){
				List<Account> objs = Database.query(soqlQuery);
				List<Map<String, Object>> rows = new List<Map<String, Object>>();

				for(Account obj : objs){
						Map<String, Object> row = new Map<String, Object>();
						row.put('Name', obj.Name);
						row.put('Phone', obj.Phone);
						row.put('NumberOfEmployees', obj.NumberOfEmployees);
						row.put('ExternalId', obj.Id);
						row.put('DisplayUrl', URL.getSalesforceBaseUrl().toExternalForm() + obj.Id);
						rows.add(row);
				}

				return rows;
		}

		/*
			用来执行 aggregation SOQL
		*/
		private Integer execCount(String soqlQuery){
				Integer count = Database.countQuery(soqlQuery);
				return count;
		}

		/*
			创建 aggregation SOQL
		*/
		private String getCountQuery(DataSource.Filter filter){
				String baseQuery = 'SELECT COUNT() FROM Account';
				String clause = getSoqlFilter('', filter);
				if(clause.length() > 0){
						return baseQuery + ' WHERE ' + filter;
				}
				return baseQuery;
		}

		/*
			创建普通 SOQL
		*/
		private String getSoqlQuery(DataSource.Filter filter){
				String baseQuery = 'SELECT Id,Name,Phone,NumberOfEmployees FROM Account';
				//String filter = getSoqlFilter('', context.tableSelection.filter);
				String clause = getSoqlFilter('', filter);
				if(clause.length() > 0){
						return baseQuery + ' WHERE ' + clause;
				}
				return baseQuery;
		}

		/*
			创建 search方法需要的 SOQL
		*/
		private String getSearchQuery(DataSource.Filter filter){
				String baseQuery = 'SELECT Id,Name,Phone,NumberOfEmployees FROM Account';

				String clause = getSoqlFilter('', filter);
				if(clause.length() > 0){
						return baseQuery + ' WHERE ' + clause;
				}
				System.debug('***baseQuery: '+baseQuery);
				return baseQuery;
		}

		/*
			用来组建 WHERE 从句

			filter为null的时候，从句为'';
			filter为符合型的时候，通过递归调用，从句为:
				NOT: NOT fieldExpression
				AND: (fieldExpressionX AND fieldExpressionY AND fieldExpressionZ)
				OR: (fieldExpressionX OR fieldExpressionY OR fieldExpressionZ)
			filter为简单型的时候，从句为fieldExpression - fieldName comparisonOperator value
		*/
		private String getSoqlFilter(String query, DataSource.Filter filter){
				if(filter == null){
					return query;
				}

				String append;
				DataSource.FilterType type = filter.type;

				if(type == DataSource.FilterType.NOT_){
						DataSource.Filter subfilter = filter.subfilters.get(0);
						append = getSoqlFilter('NOT', subfilter);
				}else if(type == DataSource.FilterType.AND_){
						append = getSoqlFilterCompound('AND', filter.subfilters);
				}else if(type == DataSource.FilterType.OR_){
						append = getSoqlFilterCompound('OR', filter.subfilters);
				}else{
						append = getSoqlFilterExpression(filter);
				}

				return query + ' ' + append;
		}

		/*
			用来处理 AND 和 OR 这两个SOQL Logical Operator
			P.S. https://developer.salesforce.com/docs/atlas.en-us.soql_sosl.meta/soql_sosl/sforce_api_calls_soql_select_logicaloperators.htm

			List<DataSource.Filter> subfilters中的每一个subfilter最后都会通过getSoqlFilter('', subfilter)方法被转换成一个fieldExpression
				如果subfilter是简单的subfilter的话，那么在getSoqlFilter()中最终是通过getSoqlFilterExpression()方法完成转换
				如果subfilter是另一个复合型subfilter的话，那么在getSoqlFilter()中递归调用getSoqlFilterCompound()方法最终完成转换

			转换后的结果就是(fieldExpressionX AND|OR fieldExpressionY AND|OR fieldExpressionZ ...)，每一个fieldExpression可能是简单的，也可能是复合型的
		*/
		private String getSoqlFilterCompound(String operator, List<DataSource.Filter> subfilters){
				String expression = ' (';
				Boolean first = true;
				for(DataSource.Filter subfilter : subfilters){
						if(first){
								first = false;
						}else{
								expression += ' ' + operator + ' ';
						}
						expression += getSoqlFilter('', subfilter);
				}
				expression += ') ';
				return expression;
		}

		/*
			把简单的filter最终转换为SOQL语句的方法
		*/
		private String getSoqlFilterExpression(DataSource.Filter filter){
				String columnName = filter.columnName;
				String operator;
				Object expectedValue = filter.columnValue;

				if(filter.type == DataSource.FilterType.EQUALS){
						operator = '=';
				}else if(filter.type == DataSource.FilterType.NOT_EQUALS){
						operator = '<>';
				}else if(filter.type == DataSource.FilterType.LESS_THAN){
						operator = '<';
				}else if(filter.type == DataSource.FilterType.GREATER_THAN){
						operator = '>';
				}else if(filter.type == DataSource.FilterType.LESS_THAN_OR_EQUAL_TO){
						operator = '<=';
				}else if(filter.type == DataSource.FilterType.GREATER_THAN_OR_EQUAL_TO){
						operator = '>=';
				}else if(filter.type == DataSource.FilterType.STARTS_WITH){
						return mapColumnName(columnName) + ' LIKE \'' + String.valueOf(expectedValue) + '%\'';
				}else if(filter.type == DataSource.FilterType.ENDS_WITH){
						return mapColumnName(columnName) + ' LIKE \'%' + String.valueOf(expectedValue) + '\'';
				}else if(filter.type == DataSource.FilterType.CONTAINS){
						return mapColumnName(columnName) + ' LIKE \'%' + String.valueOf(expectedValue) + '%\'';
				}else{
						//throw exception
				}

				return mapColumnName(columnName) + ' ' + operator + ' ' + wrapValue(expectedValue);
		}

		/*
			对字段名做必要的转换
		*/
		private String mapColumnName(String apexName){
				if(apexName.equalsIgnoreCase('ExternalId')){
						return 'Id';
				}

				if(apexName.equalsIgnoreCase('DisplayUrl')){
						return 'Id';
				}

				return apexName;
		}

		/*
			对String值加引号 - SOQL语法要求
		*/
		private String wrapValue(Object foundValue){
				if(foundValue instanceof String){
						return '\'' + String.valueOf(foundValue) + '\'';
				}

				return String.valueOf(foundValue);
		}
}
