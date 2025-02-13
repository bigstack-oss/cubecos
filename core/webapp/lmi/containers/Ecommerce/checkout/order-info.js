import React, { Component } from "react";
import { connect } from "react-redux";
import Button from "../../../components/uielements/button";
import SingleOrderInfo from "./single-order";
import { OrderTable } from "./checkout.style";

let totalPrice;

class OrderInfo extends Component {
	constructor(props) {
		super(props);
		this.renderProducts = this.renderProducts.bind(this);
	}

	renderProducts() {
		const { productQuantity, products } = this.props;
		totalPrice = 0;
		return productQuantity.map(product => {
			totalPrice += product.quantity * products[product.objectID].price;
			return (
				<SingleOrderInfo
					key={product.objectID}
					quantity={product.quantity}
					{...products[product.objectID]}
				/>
			);
		});
	}

	render() {
		return (
			<OrderTable className="isoOrderInfo">
				<div className="isoOrderTable">
					<div className="isoOrderTableHead">
						<span className="tableHead">Product</span>
						<span className="tableHead">Total</span>
					</div>

					<div className="isoOrderTableBody">{this.renderProducts()}</div>
					<div className="isoOrderTableFooter">
						<span>Total</span>
						<span>${totalPrice.toFixed(2)}</span>
					</div>

					<Button type="primary" className="isoOrderBtn">
						Place Order
					</Button>
				</div>
			</OrderTable>
		);
	}
}

function mapStateToProps(state) {
	return {
		...state.Ecommerce
	};
}
export default connect(mapStateToProps)(OrderInfo);
