global class LoopbackDataSourceProvider extends DataSource.Provider{
	/*
		决定外部数据支持哪些验证方法 - 此例中支持 ANONYMOUS 和 BASIC
		(因为本例是通过SOQL查询Account数据来模拟外部数据源，所以验证方法实际上并未使用)
	*/
	override global List<DataSource.AuthenticationCapability> getAuthenticationCapabilities(){
		List<DataSource.AuthenticationCapability> capabilities = new List<DataSource.AuthenticationCapability>();
		capabilities.add(DataSource.AuthenticationCapability.ANONYMOUS);
		capabilities.add(DataSource.AuthenticationCapability.BASIC);
		return capabilities;
	}

	/*
		决定外部数据支持哪些操作 - 此例中支持 ROW_QUERY 和 SEARCH
	*/
	override global List<Datasource.Capability> getCapabilities(){
		List<Datasource.Capability> capabilities = new List<Datasource.Capability>();
		capabilities.add(DataSource.Capability.ROW_QUERY);
		capabilities.add(DataSource.Capability.SEARCH);
		return capabilities;
	}

	/*
		返回一个Connection实例来做真正的工作
	*/
	override global DataSource.Connection getConnection(DataSource.ConnectionParams connectionParams){
		return new LoopbackDataSourceConnection();
	}
}
