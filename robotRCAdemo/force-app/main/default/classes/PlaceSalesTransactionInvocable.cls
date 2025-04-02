global with sharing class PlaceSalesTransactionInvocable {

    @InvocableMethod(label='Place Sales Transaction' description='Creates orders from a Quote, Quote Line Groups, or Quote Line Items and calls the Post Sales Transaction API.')
    public static List<OutputWrapper> placeSalesTransaction(List<InputWrapper> inputs) {
        List<OutputWrapper> results = new List<OutputWrapper>();

        // Process each input record (typically one per Flow invocation)
        for (InputWrapper input : inputs) {
            System.debug('--- Processing Input ---');
            System.debug('Input: ' + input);

            Quote q;
            List<QuoteLineItem> qliList = new List<QuoteLineItem>();
            List<QuoteLineGroup> qlgList = new List<QuoteLineGroup>();
            Boolean useGroup = false;

            // Determine which input was provided
            if (input.quoteId != null) {
                // Input is a Quote Id
                q = [SELECT Id, Name, BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry, Order_Creation_Method__c
                     FROM Quote
                     WHERE Id = :input.quoteId
                     LIMIT 1];
                System.debug('Queried Quote: ' + q);

                qliList = [SELECT Id, Product2Id, Quantity, UnitPrice, TotalPrice, Ship_To_Location__c, QuoteId
                           FROM QuoteLineItem
                           WHERE QuoteId = :q.Id];
                System.debug('Retrieved ' + qliList.size() + ' Quote Line Items for Quote Id ' + q.Id);

                if (input.quoteLineGroupIds != null && !input.quoteLineGroupIds.isEmpty()) {
                    // Query the groups provided in the input
                    qlgList = [SELECT Id, Name, QuoteId FROM QuoteLineGroup WHERE Id IN :input.quoteLineGroupIds];
                    useGroup = true;
                    System.debug('Using Quote Line Group IDs from input: ' + input.quoteLineGroupIds);
                }
            } else if (input.quoteLineGroupIds != null && !input.quoteLineGroupIds.isEmpty()) {
                // Input is a list of Quote Line Group IDs (and no Quote Id was provided)
                qlgList = [SELECT Id, Name, QuoteId FROM QuoteLineGroup WHERE Id IN :input.quoteLineGroupIds];
                if (qlgList.isEmpty()) {
                    OutputWrapper out = new OutputWrapper();
                    out.success = false;
                    out.message = 'No Quote Line Groups found for IDs: ' + input.quoteLineGroupIds;
                    results.add(out);
                    continue;
                }
                useGroup = true;
                // Derive the Quote from the first group (assuming all groups belong to the same Quote)
                QuoteLineGroup grp = qlgList[0];
                q = [SELECT Id, Name, BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry, Order_Creation_Method__c
                     FROM Quote
                     WHERE Id = :grp.QuoteId
                     LIMIT 1];
                System.debug('Queried Quote from Quote Line Groups: ' + q);
                // Query all Quote Line Items for the Quote (they’ll be filtered per group below)
                qliList = [SELECT Id, Product2Id, Quantity, UnitPrice, TotalPrice, Ship_To_Location__c, QuoteId
                           FROM QuoteLineItem
                           WHERE QuoteId = :q.Id];
                System.debug('Retrieved ' + qliList.size() + ' Quote Line Items for Quote Id ' + q.Id);
            } else if (input.quoteLineItemIds != null && !input.quoteLineItemIds.isEmpty()) {
                // Input is a list of Quote Line Item IDs
                qliList = [SELECT Id, Product2Id, Quantity, UnitPrice, TotalPrice, Ship_To_Location__c, QuoteId
                           FROM QuoteLineItem
                           WHERE Id IN :input.quoteLineItemIds];
                System.debug('Retrieved ' + qliList.size() + ' Quote Line Items from provided IDs');
                if (qliList.isEmpty()) {
                    OutputWrapper out = new OutputWrapper();
                    out.success = false;
                    out.message = 'No Quote Line Items found for the provided IDs.';
                    results.add(out);
                    continue;
                }
                // Derive the Quote from the first Quote Line Item (assumes all belong to the same Quote)
                q = [SELECT Id, Name, BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry, Order_Creation_Method__c
                     FROM Quote
                     WHERE Id = :qliList[0].QuoteId
                     LIMIT 1];
                System.debug('Queried Quote from Quote Line Items: ' + q);
            } else {
                // No valid input provided
                OutputWrapper out = new OutputWrapper();
                out.success = false;
                out.message = 'No valid input provided. Please supply a Quote ID, a list of Quote Line Group IDs, or a list of Quote Line Item IDs.';
                results.add(out);
                continue;
            }

            // Check Order Creation Method on the Quote
            if(q.Order_Creation_Method__c == 'Quote'){
                OutputWrapper out = new OutputWrapper();
                out.success = true;
                out.message = 'Order Creation Method is Quote. No processing is performed by this invocable class.';
                results.add(out);
                continue;
            }

            // For Order Creation Methods "Group" or "Quote Line Custom", enforce grouping.
            if (q.Order_Creation_Method__c == 'Group' || q.Order_Creation_Method__c == 'Quote Line Custom') {
                useGroup = true;
                // If no groups were provided in the input, query all groups for this Quote.
                if ((input.quoteLineGroupIds == null || input.quoteLineGroupIds.isEmpty()) && (qlgList == null || qlgList.isEmpty())) {
                    qlgList = [SELECT Id, Name FROM QuoteLineGroup WHERE QuoteId = :q.Id];
                }
            }

            // If grouping is used, create a separate order per group.
            if (useGroup && !qlgList.isEmpty()) {
                List<String> allOrderIds = new List<String>();
                Boolean overallSuccess = true;
                String overallMessage = '';
                for (QuoteLineGroup grpRec : qlgList) {
                    // Build order line for this group
                    List<Map<String, Object>> orderLines = new List<Map<String, Object>>();
                    Map<String, Object> orderLine = new Map<String, Object>();
                    orderLine.put('groupName', grpRec.Name);
                    List<Map<String, Object>> lineItems = new List<Map<String, Object>>();
                    for (QuoteLineItem qli : qliList) {
                        if (qli.Ship_To_Location__c == grpRec.Id) {
                            Map<String, Object> item = new Map<String, Object>{
                                'productId' => qli.Product2Id,
                                'quantity'  => qli.Quantity,
                                'unitPrice' => qli.UnitPrice,
                                'totalPrice'=> qli.TotalPrice
                            };
                            lineItems.add(item);
                        }
                    }
                    orderLine.put('lineItems', lineItems);
                    orderLines.add(orderLine);

                    // Build order header (same for all groups)
                    Map<String, Object> orderHeader = new Map<String, Object>{
                        'orderName'         => q.Name,
                        'billingStreet'     => q.BillingStreet,
                        'billingCity'       => q.BillingCity,
                        'billingState'      => q.BillingState,
                        'billingPostalCode' => q.BillingPostalCode,
                        'billingCountry'    => q.BillingCountry
                    };
                    Map<String, Object> salesTransaction = new Map<String, Object>{
                        'orderHeader' => orderHeader,
                        'orderLines'  => orderLines
                    };
                    String jsonRequest = JSON.serialize(new Map<String, Object>{ 'salesTransaction' => salesTransaction });
                    System.debug('Sales Transaction Request JSON for group ' + grpRec.Id + ': ' + jsonRequest);

                    HttpRequest req = new HttpRequest();
                    req.setEndpoint('https://bluerobotrca-dev-ed.develop.lightning.force.com/services/apexrest/salesTransaction');
                    req.setMethod('POST');
                    req.setHeader('Content-Type', 'application/json');
                    req.setBody(jsonRequest);

                    Http http = new Http();
                    try {
                        HttpResponse res = http.send(req);
                        System.debug('HTTP Response Status for group ' + grpRec.Id + ': ' + res.getStatus());
                        System.debug('HTTP Response Body for group ' + grpRec.Id + ': ' + res.getBody());
                        if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
                            Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                            List<Object> orderIds = (List<Object>) responseBody.get('orderIds');
                            if (orderIds != null) {
                                for (Object oid : orderIds) {
                                    allOrderIds.add(String.valueOf(oid));
                                }
                            }
                        } else {
                            overallSuccess = false;
                            overallMessage += 'Error for group ' + grpRec.Id + ': ' + res.getStatusCode() + ' ' + res.getBody() + '; ';
                        }
                    } catch(Exception ex) {
                        overallSuccess = false;
                        overallMessage += 'Callout Exception for group ' + grpRec.Id + ': ' + ex.getMessage() + '; ';
                    }
                }
                OutputWrapper out = new OutputWrapper();
                out.success = overallSuccess;
                out.message = overallSuccess ? 'Sales transactions placed successfully for all groups.' : overallMessage;
                out.orderIds = allOrderIds;
                results.add(out);
            } else {
                // Not grouping: create one order with all Quote Line Items
                Map<String, Object> orderHeader = new Map<String, Object>{
                    'orderName'         => q.Name,
                    'billingStreet'     => q.BillingStreet,
                    'billingCity'       => q.BillingCity,
                    'billingState'      => q.BillingState,
                    'billingPostalCode' => q.BillingPostalCode,
                    'billingCountry'    => q.BillingCountry
                };
                List<Map<String, Object>> orderLines = new List<Map<String, Object>>();
                Map<String, Object> orderLine = new Map<String, Object>();
                List<Map<String, Object>> lineItems = new List<Map<String, Object>>();
                for (QuoteLineItem qli : qliList) {
                    Map<String, Object> item = new Map<String, Object>{
                        'productId' => qli.Product2Id,
                        'quantity'  => qli.Quantity,
                        'unitPrice' => qli.UnitPrice,
                        'totalPrice'=> qli.TotalPrice
                    };
                    lineItems.add(item);
                }
                orderLine.put('lineItems', lineItems);
                orderLines.add(orderLine);
                Map<String, Object> salesTransaction = new Map<String, Object>{
                    'orderHeader' => orderHeader,
                    'orderLines'  => orderLines
                };
                String jsonRequest = JSON.serialize(new Map<String, Object>{ 'salesTransaction' => salesTransaction });
                System.debug('Sales Transaction Request JSON: ' + jsonRequest);

                HttpRequest req = new HttpRequest();
                req.setEndpoint('https://bluerobotrca-dev-ed.develop.lightning.force.com/services/apexrest/salesTransaction');
                req.setMethod('POST');
                req.setHeader('Content-Type', 'application/json');
                req.setBody(jsonRequest);

                Http http = new Http();
                OutputWrapper output = new OutputWrapper();
                try {
                    HttpResponse res = http.send(req);
                    System.debug('HTTP Response Status: ' + res.getStatus());
                    System.debug('HTTP Response Body: ' + res.getBody());
                    if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {
                        Map<String, Object> responseBody = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                        List<Object> orderIds = (List<Object>) responseBody.get('orderIds');
                        output.success = true;
                        output.message = 'Sales transaction placed successfully.';
                        output.orderIds = new List<String>();
                        if (orderIds != null) {
                            for (Object oid : orderIds) {
                                output.orderIds.add(String.valueOf(oid));
                            }
                        }
                    } else {
                        output.success = false;
                        output.message = 'Error: ' + res.getStatusCode() + ' ' + res.getBody();
                    }
                } catch(Exception ex) {
                    output.success = false;
                    output.message = 'Callout Exception: ' + ex.getMessage();
                }
                results.add(output);
            }

        } // End for each input record

        System.debug('Final Results: ' + results);
        return results;
    }

    // Input wrapper to support different types of input records
    public class InputWrapper {
        @InvocableVariable(required=false)
        public Id quoteId;

        @InvocableVariable(required=false)
        public List<Id> quoteLineGroupIds;

        @InvocableVariable(required=false)
        public List<Id> quoteLineItemIds;
    }

    // Output wrapper to return results to the Flow
    public class OutputWrapper {
        @InvocableVariable
        public Boolean success;

        @InvocableVariable
        public String message;

        @InvocableVariable
        public List<String> orderIds;
    }
}