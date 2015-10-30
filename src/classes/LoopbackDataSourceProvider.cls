global class LoopbackDataSourceProvider extends DataSource.Provider{

		override global List<DataSource.AuthenticationCapability> getAuthenticationCapabilities(){
				List<DataSource.AuthenticationCapability> capabilities = new List<DataSource.AuthenticationCapability>();
				capabilities.add(DataSource.AuthenticationCapability.ANONYMOUS);
				capabilities.add(DataSource.AuthenticationCapability.BASIC);
				return capabilities;
		}

		override global List<Datasource.Capability> getCapabilities(){
				List<Datasource.Capability> capabilities = new List<Datasource.Capability>();
				capabilities.add(DataSource.Capability.ROW_QUERY);
				capabilities.add(DataSource.Capability.SEARCH);
				return capabilities;
		}

		override global DataSource.Connection getConnection(DataSource.ConnectionParams connectionParams){
				return new LoopbackDataSourceConnection();
		}
}