Test for emulating OLTP workload on Firebird DBMS. Supports all FB versions since 2.5.

The model of test is based on real business processes of a car-service enterprise:
1. A customer does order (wants we supply him some set of parts); we also can make order for our purposes;
2. We gather several customer orders, unite them into single document and send it to supplier;
3. Supplier sends us invoice which can fully or partially satisfy our demands.
4. When we receive invoice its content is added to stock remainders. 
   Parts that were ordered by customer will be immediately reserved for saling.
5. Further we sale ordered parts and make appropriate write-off from stock.
6. All previously mentioned operations can be cancelled in any step.
7. Each client order and each our invoice to supplier can be paid for 100% or less, and this must be reflected
   in customer or supplire balance (separately). Each payment operation can be cancelled.
8. After test finish first of running session invokes reports about performance (total and detailed),
   list of occured exceptions, database statistics, result of DB validation et al.
