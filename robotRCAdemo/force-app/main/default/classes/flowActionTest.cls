public class DiscoverProductFlowAction {
    
    // Define input parameters
    public class FlowInput {
        @InvocableVariable(required=false)
        public String PPAccountRecordType;
        
        @InvocableVariable(required=false)
        public String PPAccountBand;
    }
    
    // Define output parameters     
    public class FlowOutput {
        @InvocableVariable
        public runtime_industries_cpq.ContextDataInput[] additionalContextData;
    }

    // This method is invoked from a flow
    @InvocableMethod(label='Process Input' description='Creates the Array of ContextDataInput for additional Context Data')
    public static List<FlowOutput> generateAdditionalContextData(List<FlowInput> inputs) {
        String ppAccountRecordType;
        String ppAccountBand;
        FlowOutput output = new FlowOutput();
        
        // Capture input from the flow
        for(FlowInput input : inputs ){
            ppAccountRecordType = input.PPAccountRecordType;
            ppAccountBand = input.PPAccountBand;
        }

        // Populate the ContextDataInput list to store additional context data
        List<runtime_industries_cpq.ContextDataInput> listContextData = new List<runtime_industries_cpq.ContextDataInput>();
        
        // CategoryProduct Node
        runtime_industries_cpq.ContextDataInput cd2 = new runtime_industries_cpq.ContextDataInput();
        cd2.nodeName = 'PricingProduct';
        cd2.nodeData = new Map<String,Object>();
        cd2.nodeData.put('PPAccountRecordType', ppAccountRecordType);
        cd2.nodeData.put('PPAccountBand', ppAccountBand);
        listContextData.add(cd2);
        
        // Return the additional Context Data to a flow
        output.additionalContextData = listContextData;
        return new List<FlowOutput>{output};       
    }
}