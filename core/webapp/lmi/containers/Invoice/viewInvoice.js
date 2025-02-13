import React, { Component } from 'react';
import Link from 'next/link';
import moment from 'moment';
import Box from '../../components/utility/box';
import { ViewTable } from '../../components/invoice/invoiceTable';
import Button from '../../components/uielements/button';
import LayoutWrapper from '../../components/utility/layoutWrapper.js';
import InvoiceAddress from '../../components/invoice/address';
import InvoicePageWrapper from './singleInvoice.style';

export default class extends Component {
	render() {
		const { currentInvoice, toggleView, redirectPath } = this.props;
		return (
			<LayoutWrapper>
				<Box>
					<InvoicePageWrapper className="InvoicePageWrapper">
						<div className="PageHeader">
							<Link href={redirectPath}>
								<Button className="isoGoInvoBtn">
									<span>Go To Invoices</span>
								</Button>
							</Link>
							<Button color="secondary" onClick={() => toggleView(true)}>
								<span>Edit Invoice</span>
							</Button>
							<Button type="primary" className="isoInvoPrint">
								<span>Print Invoice</span>
							</Button>
						</div>

						<div className="PageContent">
							<div className="OrderInfo">
								<div className="LeftSideContent">
									<h3 className="Title">Invoice Info</h3>
									<span className="InvoiceNumber">{currentInvoice.number}</span>
								</div>
								<div className="RightSideContent">
									<p>
										<span className="orderStatusSpan">Order Status: </span>
										<span className="orderStatus">
											{currentInvoice.orderStatus}
										</span>
									</p>
									<p>
										<span className="orderDateSpan">Order date: </span>
										<span className="orderDate">
											{moment(new Date(currentInvoice.orderDate)).format(
												'MMMM Do YYYY'
											)}
										</span>
									</p>
								</div>
							</div>
							<div className="BillingInformation">
								<div className="LeftSideContent">
									<h3 className="Title">Bill From</h3>

									<InvoiceAddress
										companyName={currentInvoice.billFrom}
										companyAddress={currentInvoice.billFromAddress}
									/>
								</div>
								<div className="RightSideContent">
									<h3 className="Title">Bill To</h3>

									<InvoiceAddress
										companyName={currentInvoice.billTo}
										companyAddress={currentInvoice.billToAddress}
									/>
								</div>
							</div>
							<div className="InvoiceTable">
								<ViewTable invoiceList={currentInvoice.invoiceList} />
								<div className="TotalBill">
									<p>
										Sub-total :{' '}
										<span>{`${currentInvoice.currency}${
											currentInvoice.subTotal
										}`}</span>
									</p>
									<p>
										Vat :{' '}
										<span>{`${currentInvoice.currency}${
											currentInvoice.vatPrice
										}`}</span>
									</p>
									<h3>
										Grand Total :{' '}
										<span>{`${currentInvoice.currency}${
											currentInvoice.totalCost
										}`}</span>
									</h3>
								</div>
							</div>
							<div className="ButtonWrapper">
								<Button type="primary" className="mateInvoPrint">
									<span>Send Invoice</span>
								</Button>
							</div>
						</div>
					</InvoicePageWrapper>
				</Box>
			</LayoutWrapper>
		);
	}
}
