import React, { Component } from 'react';
import Link from 'next/link';
import moment from 'moment';
import { EditTable } from '../../components/invoice/invoiceTable';
import OrderStatus from '../../components/invoice/orderStatus';
import notification from '../../components/notification';
import Button from '../../components/uielements/button';
import Input, { Textarea } from '../../components/uielements/input';
import DatePicker from '../../components/uielements/datePicker';
import Box from '../../components/utility/box';
import LayoutWrapper from '../../components/utility/layoutWrapper.js';
import InvoicePageWrapper from './singleInvoice.style';
import { stringToPosetiveInt } from '../../helpers/utility';
import { orderStatusOptions } from './config';

const updateValues = invoice => {
	const { invoiceList } = invoice;
	let subTotal = 0;
	invoiceList.forEach((item, index) => {
		const price = item.costs * item.qty;
		invoice.invoiceList[index].price = price;
		invoice.invoiceList[index].key = index + 1;
		subTotal += price;
	});
	invoice.subTotal = subTotal;
	invoice.vatPrice = Math.floor(invoice.vatRate * subTotal * 0.01);
	invoice.totalCost = invoice.vatPrice + subTotal;
	return invoice;
};
const checkInvoice = invoice => {
	const emptyKeys = [
		'number',
		'billTo',
		'billToAddress',
		'billFrom',
		'billFromAddress',
		'currency',
	];
	const emptyKeysErrors = [
		'Invoice Number',
		'Bill To',
		'Bill To Address',
		'Bill From',
		'Bill From Address',
		'Currency',
	];
	for (let i = 0; i < emptyKeys.length; i++) {
		if (!invoice[emptyKeys[i]]) {
			return `Please fill in ${emptyKeysErrors[i]}`;
		}
	}
	for (let i = 0; i < invoice.invoiceList.length; i++) {
		if (!invoice.invoiceList[i].itemName) {
			return `Please fill in item name of ${i + 1} item`;
		}
		if (invoice.invoiceList[i].costs === 0) {
			return `cost of ${i + 1} item should be positive`;
		}
		if (invoice.invoiceList[i].qty === 0) {
			return `quantity of ${i + 1} item should be positive`;
		}
	}
	return '';
};

export default class extends Component {
	onSave = () => {
		const { editableInvoice, isNewInvoice, updateInvoice } = this.props;
		const error = checkInvoice(editableInvoice);
		if (error) {
			notification('error', error);
		} else {
			const successMessage = isNewInvoice
				? 'A new Invoice added'
				: 'Invoice Updated';
			notification('success', successMessage);
			updateInvoice(editableInvoice);
		}
	};
	render() {
		const {
			editableInvoice,
			isNewInvoice,
			redirectPath,
			toggleView,
			editInvoice,
		} = this.props;
		return (
			<LayoutWrapper>
				<Box>
					<InvoicePageWrapper className="editView">
						<div className="PageHeader">
							{isNewInvoice ? (
								<Link href={redirectPath}>
									<Button color="primary">
										<span>Cancel</span>
									</Button>
								</Link>
							) : (
								<Button onClick={() => toggleView(false)}>
									<span>Cancel</span>
								</Button>
							)}

							<Button type="primary" onClick={this.onSave} className="saveBtn">
								<span>Save</span>
							</Button>
						</div>
						<div className="PageContent">
							<div className="OrderInfo">
								<div className="LeftSideContent">
									<h3 className="Title">Invoice Info</h3>
									<Input
										placeholder="Number"
										value={editableInvoice.number}
										onChange={event => {
											editableInvoice.number = event.target.value;
											editInvoice(editableInvoice);
										}}
										className="LeftSideContentInput"
									/>
								</div>
								<div className="RightSideContent">
									<div className="RightSideStatus">
										<span className="RightSideStatusSpan">Order Status: </span>
										<OrderStatus
											value={editableInvoice.orderStatus}
											onChange={orderStatus => {
												editableInvoice.orderStatus = orderStatus;
												editInvoice(editableInvoice);
											}}
											orderStatusOptions={orderStatusOptions}
											className="RightStatusDropdown"
										/>
									</div>
									<div className="RightSideDate">
										Order date:{' '}
										<DatePicker
											allowClear={false}
											value={moment(new Date(editableInvoice.orderDate))}
											onChange={val => {
												editableInvoice.orderDate = val.toDate().getTime();
												editInvoice(editableInvoice);
											}}
											format="MMMM Do YYYY"
											animateYearScrolling={true}
										/>
									</div>
								</div>
							</div>
							<div className="BillingInformation">
								<div className="LeftSideContent">
									<Input
										placeholder="Bill From"
										value={editableInvoice.billFrom}
										onChange={event => {
											editableInvoice.billFrom = event.target.value;
											editInvoice(editableInvoice);
										}}
										className="BillFormTitle"
									/>
									<Textarea
										placeholder="Bill From Address"
										value={editableInvoice.billFromAddress}
										rows={5}
										onChange={event => {
											editableInvoice.billFromAddress = event.target.value;
											editInvoice(editableInvoice);
										}}
										className="BillFormAddress"
									/>
								</div>
								<div className="RightSideContent">
									<Input
										placeholder="Bill To"
										value={editableInvoice.billTo}
										onChange={event => {
											editableInvoice.billTo = event.target.value;
											editInvoice(editableInvoice);
										}}
										className="BillFormTitle"
									/>
									<Textarea
										placeholder="Bill To Address"
										value={editableInvoice.billToAddress}
										rows={5}
										onChange={event => {
											editableInvoice.billToAddress = event.target.value;
											editInvoice(editableInvoice);
										}}
										className="BillFormAddress"
									/>
								</div>
							</div>

							<div className="InvoiceTable editInvoiceTable">
								<EditTable
									editableInvoice={editableInvoice}
									editInvoice={editInvoice}
									updateValues={updateValues}
								/>
								<div className="InvoiceTableBtn">
									<Button
										onClick={() => {
											editableInvoice.invoiceList.push({
												key: editableInvoice.invoiceList.length + 1,
												itemName: '',
												costs: 0,
												qty: 0,
												price: 0,
											});
											editInvoice(editableInvoice);
										}}
										type="primary"
									>
										Add Item
									</Button>
								</div>
								<div className="TotalBill">
									<p>
										<span className="TotalBillTitle">Sub-total : </span>
										<span>{`${editableInvoice.currency}${
											editableInvoice.subTotal
										}`}</span>
									</p>
									<div className="vatRateCalc">
										<span className="vatRateCalcSpan"> Total Vat : </span>
										<div className="vatRateCalcWrap">
											<Input
												value={editableInvoice.vatRate}
												addonAfter="%"
												onChange={event => {
													editableInvoice.vatRate = stringToPosetiveInt(
														event.target.value,
														editableInvoice.vatRate
													);
													editInvoice(updateValues(editableInvoice));
												}}
											/>

											<span>
												{`${editableInvoice.currency}${
													editableInvoice.vatPrice
												}`}
											</span>
										</div>
									</div>
									<div className="currencySignWithTotal">
										<span className="grandTotalSpan">Grand Total </span>
										<div className="currencySignWrap">
											<Input
												value={editableInvoice.currency}
												onChange={event => {
													editableInvoice.currency = event.target.value;
													editInvoice(editableInvoice);
												}}
												className="currencySign"
											/>
											<span className="currencySignSpan">
												{editableInvoice.totalCost}
											</span>
										</div>
									</div>
								</div>
							</div>
							<div className="ButtonWrapper" />
						</div>
					</InvoicePageWrapper>
				</Box>
			</LayoutWrapper>
		);
	}
}
