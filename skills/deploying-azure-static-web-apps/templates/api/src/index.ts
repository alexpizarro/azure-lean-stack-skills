// Entry point — importing each file registers its functions with the Azure Functions runtime.
// EVERY new function file MUST be imported here, or its route silently returns 404 (gotcha #16).
import './functions/health';
import './functions/hello';
import './functions/getItems';
import './functions/createItem';
