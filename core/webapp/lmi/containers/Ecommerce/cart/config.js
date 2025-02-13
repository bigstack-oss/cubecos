const productDatas = [];
function getInitData() {
  let productQuantity = [];
  const products = {};
  const cartProductQuantity = null//localStorage.getItem("cartProductQuantity");
  let cartProducts = null//localStorage.getItem("cartProducts");
  if (cartProducts && cartProductQuantity) {
    cartProducts = JSON.parse(cartProducts);
    JSON.parse(cartProductQuantity).forEach(product => {
      const objectID = product.objectID;
      if (!isNaN(product.quantity)) {
        productQuantity.push({
          objectID,
          quantity: parseInt(product.quantity, 10)
        });
        products[objectID] = {
          ...cartProducts[objectID],
          price: parseFloat(cartProducts[objectID].price, 10)
        };
      }
    });
  } else {
    productDatas.forEach(product => {
      productQuantity.push({
        objectID: product.objectID,
        quantity: 1
      });
      products[product.objectID] = product;
    });
  }
  return { productQuantity, products };
}

export default getInitData();
