import styled from 'styled-components';
import { palette } from 'styled-theme';
import WithDirection from '../../config/withDirection';

const InvoicePageWrapper = styled.div`
	.PageHeader {
		width: 100%;
		display: -webkit-box;
		display: -webkit-flex;
		display: -ms-flexbox;
		display: flex;
		-webkit-flex-flow: row wrap;
		-ms-flex-flow: row wrap;
		flex-flow: row wrap;
		-webkit-align-items: flex-end;
		-webkit-box-align: flex-end;
		-ms-flex-align: flex-end;
		align-items: flex-end;
		-webkit-box-pack: justify;
		-webkit-justify-content: flex-end;
		-ms-flex-pack: justify;
		justify-content: flex-end;
		margin-bottom: 30px;

		@media (max-width: 479px) {
			justify-content: ${props =>
				props['data-rtl'] === 'rtl' ? 'flex-end' : 'flex-start'};
		}

		a {
			text-decoration: none;
		}
		.isoGoInvoBtn {
			margin-right: 15px;
		}
		.isoInvoPrint {
			background: ${palette('blue', 14)};
			margin: ${props =>
				props['data-rtl'] === 'rtl' ? '0 15px 0 0' : '0 0 0 15px'};
			@media (max-width: 500px) {
				margin-top: 15px;
			}
			@media (max-width: 479px) {
				margin: 0;
			}
		}
		.saveBtn {
			background: ${palette('blue', 14)};
			margin: ${props =>
				props['data-rtl'] === 'rtl' ? '0 15px 0 0' : '0 0 0 15px'};
		}
	}

	.PageContent {
		.OrderInfo {
			width: 100%;
			display: -webkit-box;
			display: -webkit-flex;
			display: -ms-flexbox;
			display: flex;
			-webkit-flex-flow: row wrap;
			-ms-flex-flow: row wrap;
			flex-flow: row wrap;
			-webkit-align-items: baseline;
			-webkit-box-align: baseline;
			-ms-flex-align: baseline;
			align-items: baseline;
			-webkit-box-pack: justify;
			-webkit-justify-content: space-between;
			-ms-flex-pack: justify;
			justify-content: space-between;
			padding-bottom: 30px;
			border-bottom: 1px dashed ${palette('grayscale', 2)};

			@media (max-width: 560px) {
				flex-direction: column;
			}

			.Title {
				font-size: 16px;
				font-weight: 500;
				color: ${palette('grey', 8)};
				margin: 0 0 20px;
				line-height: 1;
			}

			span.InvoiceNumber {
				font-size: 16px;
				font-weight: 400;
				color: ${palette('blue', 11)};
				margin: 0;
			}

			.RightSideContent {
				display: flex;
				flex-direction: column;

				@media (max-width: 769px) {
					align-items: flex-start;
				}

				@media (max-width: 560px) {
					margin-top: 30px;
				}

				p {
					font-size: 14px;
					color: ${palette('grey', 8)};
					margin: 0 0 15px;
					font-weight: 500;

					span.orderStatus {
						margin-left: ${props =>
							props['data-rtl'] === 'rtl' ? '0 8px 0 0' : '0 0 0 8px'};
						font-weight: 400;
					}
					span.orderDate {
						font-weight: 400;
						margin-left: ${props =>
							props['data-rtl'] === 'rtl' ? '0 8px 0 0' : '0 0 0 8px'};
					}

					&:last-child {
						margin: 0;
					}
					.orderStatusSpan {
						font-size: 14px;
						color: ${palette('grey', 8)};
						margin: 0 0 15px;
						font-weight: 500;
					}
					.orderDateSpan {
						font-size: 14px;
						color: ${palette('grey', 8)};
						margin: 0 0 15px;
						margin-left: ${props =>
							props['data-rtl'] === 'rtl' ? '0 13px 0 0' : '0 0 0 13px'};
						font-weight: 500;

						@media (max-width: 420px) {
							margin: 0;
						}
					}
				}
				.RightSideStatus {
					display: flex;
					flex-direction: row;
					align-items: center;
					font-size: 14px;
					color: ${palette('grey', 8)};

					@media (max-width: 560px) {
						margin-bottom: 10px;
					}

					.RightSideStatusSpan {
						margin: ${props =>
							props['data-rtl'] === 'rtl' ? '0 -10px 0 7px' : '0 7px 0 -10px'};

						@media (max-width: 560px) {
							margin: ${props =>
								props['data-rtl'] === 'rtl' ? '0 0 0 10px' : '0 10px 0 0'};
						}
					}
					#order-drop-list {
						z-index: 1;
					}
				}
				.RightSideDate {
					display: flex;
					flex-direction: row;
					align-items: center;
					margin-top: 15px;
					font-size: 14px;
					color: ${palette('grey', 8)};
					> span {
						margin: ${props =>
							props['data-rtl'] === 'rtl' ? '0 10px 0 0' : '0 0 0 10px'};
					}

					@media (max-width: 560px) {
						margin: ${props =>
							props['data-rtl'] === 'rtl' ? '0 13px 0 0' : '0 0 0 13px'};
					}

					> div {
						margin: ${props =>
							props['data-rtl'] === 'rtl' ? '0 7px 0 0' : '0 0 0 7px'};
						> div {
							&::before {
								background-color: #ececec;
							}
						}
					}
				}
			}
			.LeftSideContent {
				.LeftSideContentInput {
					> div {
						&::before {
							background-color: #ececec;
						}
					}
				}
			}
		}

		.LeftSideContent {
			display: -webkit-box;
			display: -webkit-flex;
			display: -ms-flexbox;
			display: flex;
			-webkit-align-items: flex-start;
			-webkit-box-align: flex-start;
			-ms-flex-align: flex-start;
			align-items: flex-start;
			-webkit-flex-direction: column;
			-ms-flex-direction: column;
			flex-direction: column;
			&.LeftSideContentInput {
				> div {
					&::before {
						background-color: #ececec;
					}
				}
			}
		}

		.RightSideContent {
			display: -webkit-box;
			display: -webkit-flex;
			display: -ms-flexbox;
			display: flex;
			-webkit-align-items: flex-end;
			-webkit-box-align: flex-end;
			-ms-flex-align: flex-end;
			align-items: flex-end;
			-webkit-flex-direction: column;
			-ms-flex-direction: column;
			flex-direction: column;
			text-align: right;

			@media only screen and (max-width: 767px) {
				-webkit-align-items: flex-start;
				-webkit-box-align: flex-start;
				-ms-flex-align: flex-start;
				align-items: flex-start;
				text-align: left;
			}

			@media only screen and (min-width: 501px) and (max-width: 767px) {
				-webkit-align-items: flex-end;
				-webkit-box-align: flex-end;
				-ms-flex-align: flex-end;
				align-items: flex-end;
				text-align: right;
			}
		}

		.BillingInformation {
			width: 100%;
			display: -webkit-box;
			display: -webkit-flex;
			display: -ms-flexbox;
			display: flex;
			-webkit-flex-flow: row wrap;
			-ms-flex-flow: row wrap;
			flex-flow: row wrap;
			-webkit-align-items: baseline;
			-webkit-box-align: baseline;
			-ms-flex-align: baseline;
			align-items: baseline;
			-webkit-box-pack: justify;
			-webkit-justify-content: space-between;
			-ms-flex-pack: justify;
			justify-content: space-between;
			margin-top: 50px;
			margin-bottom: 60px;

			.LeftSideContent,
			.RightSideContent {
				width: calc(50% - 50px);
				margin: ${props =>
					props['data-rtl'] === 'rtl' ? '0 0 0 10px' : '0 10px 0 0'};

				@media (max-width: 500px) {
					width: 100%;
					margin: 0;
				}
			}
			.RightSideContent {
				margin: 0;

				input,
				textarea {
					text-align: ${props =>
						props['data-rtl'] === 'rtl' ? 'left' : 'right'};
				}
			}
			@media only screen and (max-width: 767px) {
				.RightSideContent {
					margin-top: 40px;
				}
			}

			h3.Title,
			.BillFormTitle {
				font-size: 16px;
				font-weight: 500;
				color: ${palette('grey', 9)};
				margin: 0 0 10px;
				line-height: 1;
				label {
					font-size: 19px;
					font-weight: 500;
					color: ${palette('grey', 9)};
					margin: 0 0 10px;
					line-height: 1;
				}
				> div {
					&::before {
						background-color: #ececec;
					}
				}
				input {
					font-size: 15px;
					color: ${palette('grey', 7)};
					font-weight: 400;
					display: block;
					margin-top: 10px;
				}
			}
			.BillFormAddress {
				width: 100%;
				> div {
					&::before {
						background-color: #ececec;
					}
				}
				textarea {
					height: 100%;
					overflow: hidden;
					font-size: 14px;
					color: ${palette('grey', 7)};
					font-weight: 300;
					font-style: normal;
				}
				textarea.ant-input {
					min-height: 160px !important;
				}
			}
			p.NameEmail {
				span.Name {
					font-size: 15px;
					color: ${palette('grey', 7)};
					font-weight: 400;
					display: block;
				}

				span.Email {
					font-size: 14px;
					color: ${palette('grey', 7)};
					font-weight: 300;
				}
			}

			address {
				font-size: 14px;
				color: ${palette('grey', 7)};
				font-weight: 300;
				font-style: normal;
			}
		}
		.customScrollBar {
			.scrollbar-thumb {
				&.scrollbar-thumb-y {
					display: none !important;
				}
			}
		}
		.InvoiceTable {
			table {
				thead {
					background-color: ${palette('grey', 2)};
					tr {
						th {
							color: ${palette('grey', 8)};
						}
					}
				}

				tbody {
					tr {
						td {
							color: ${palette('grey', 7)};
							> div {
								> div {
									&::before {
										background-color: #ececec;
									}
								}
							}
							input {
								color: ${palette('grey', 7)};
								font-size: 0.8125rem;
							}
							.material-icons {
								color: #757575;
							}
						}
					}
				}
			}
			.InvoiceTableBtn {
				display: flex;
				justify-content: ${props =>
					props['data-rtl'] === 'rtl' ? 'flex-start' : 'flex-end'};
				align-items: ${props =>
					props['data-rtl'] === 'rtl' ? 'flex-start' : 'flex-end'};
				margin-top: 15px;
				.InvoiceEditAddBtn {
					background: ${palette('blue', 14)};
					color: #fff;
				}
			}
			.TotalBill {
				margin-top: 30px;
				display: -webkit-box;
				display: -webkit-flex;
				display: -ms-flexbox;
				display: flex;
				width: 100%;
				align-items: ${props =>
					props['data-rtl'] === 'rtl' ? 'flex-start' : 'flex-end'};
				text-align: ${props =>
					props['data-rtl'] === 'rtl' ? 'left' : 'right'};
				flex-direction: column;
				padding-left: inherit;

				p {
					margin-top: 0;
					font-size: 14px;
					color: ${palette('grey', 7)};
					margin-bottom: 15px;
					width: 250px;
					display: flex;
					justify-content: ${props =>
						props['data-rtl'] === 'rtl' ? 'flex-start' : 'flex-end'};
					text-align: ${props =>
						props['data-rtl'] === 'rtl' ? 'left' : 'right'};

					span {
						width: 120px;
					}
				}
				.TotalBillTitle {
					margin: ${props =>
						props['data-rtl'] === 'rtl' ? '0 0 0 -10px' : '0 -10px 0 0'};
				}
				.totalVat {
					width: 186px;
				}
				.vatRateCalc {
					> div {
						margin-top: -12px;
						width: 25px;
						margin: ${props =>
							props['data-rtl'] === 'rtl' ? '0 15px 0 0' : '0 0 0 15px'};
						> div {
							&::before {
								background-color: #ececec;
							}
						}
					}
					input {
						color: ${palette('grey', 7)};
						font-size: 14px;
					}
					> span {
						width: 70px;
						margin: ${props =>
							props['data-rtl'] === 'rtl' ? '-7px 10px 0 0' : '-7px 0 0 10px'};
					}
					.ant-input-group-wrapper {
						width: auto;
						margin: ${props =>
							props['data-rtl'] === 'rtl' ? '-7px 0 0 0' : '-7px 0 0 0'};
						box-sizing: border-box;
						display: inline-block;
						vertical-align: top;
					}
					.vatRateCalcWrap {
						> span:last-child {
							margin: ${props =>
								props['data-rtl'] === 'rtl'
									? '-7px 10px 0 0'
									: '-7px 0 0 10px'};
						}
					}
					.ant-input-wrapper.ant-input-group {
						margin: ${props =>
							props['data-rtl'] === 'rtl' ? '0 -22px 0 0' : '0 0 0 -22px'};
						margin-top: 0;
						input.ant-input {
							width: 50px;
						}
					}
				}
				.currencySign {
					> div {
						&::before {
							background-color: #ececec;
						}
					}
					input,
					label {
						color: ${palette('grey', 7)};
						font-size: 14px;
					}
				}
				h3 {
					font-size: 18px;
					color: ${palette('grey', 9)};
					margin: 0;
					font-weight: 400;
					width: 250px;
					display: flex;
					justify-content: ${props =>
						props['data-rtl'] === 'rtl' ? 'flex-start' : 'flex-end'};
					text-align: ${props =>
						props['data-rtl'] === 'rtl' ? 'left' : 'right'};

					span {
						width: 120px;
					}
				}
				.currencySignWithTotal {
					span {
						width: 100%;
					}
					.currencySign {
						margin: ${props =>
							props['data-rtl'] === 'rtl' ? '0 10px 0 0' : '0 0 0 10px'};
						width: 50px;
						margin-top: -5px;
					}
					.currencySignSpan {
						width: 120px;
					}
				}
				.grandTotal {
					margin-top: 15px;
				}
			}
			&.editInvoiceTable {
				table {
					@media (max-width: 767px) {
						width: 760px;
					}
					thead {
						background-color: ${palette('secondary', 1)};
						tr {
							th {
								color: ${palette('secondary', 2)};
							}
						}
					}

					tbody {
						tr {
							td {
								color: ${palette('text', 1)};
								border-bottom: 0;
								padding: 8px 15px;
								> div {
									> div {
										&::before {
											background-color: #ececec;
										}
									}
								}
								input {
									color: ${palette('text', 1)};
									font-size: 0.8125rem;
									height: 28px;
								}
								.material-icons {
									color: #757575;
								}
							}
						}
					}
				}
				.TotalBill {
					p {
						width: 300px;
						justify-content: ${props =>
							props['data-rtl'] === 'rtl' ? 'flex-start' : 'flex-end'};
						text-align: ${props =>
							props['data-rtl'] === 'rtl' ? 'left' : 'right'};
						span {
							width: 50%;
						}
						span.TotalBillTitle {
							margin-right: ${props =>
								props['data-rtl'] === 'rtl' ? 'inherit' : '0'};
							margin-left: ${props =>
								props['data-rtl'] === 'rtl' ? '0' : 'inherit'};
						}
					}
					.vatRateCalc {
						width: 300px;
						display: flex;
						justify-content: ${props =>
							props['data-rtl'] === 'rtl' ? 'flex-end' : 'flex-start'};
						.vatRateCalcSpan {
							width: 50%;
						}
						.vatRateCalcWrap {
							width: 50%;
							margin-top: -5px;
							margin-left: ${props =>
								props['data-rtl'] === 'rtl' ? 'inherit' : '0'};
							margin-right: ${props =>
								props['data-rtl'] === 'rtl' ? '0' : 'inherit'};
							.ant-input-wrapper.ant-input-group {
								margin-left: ${props =>
									props['data-rtl'] === 'rtl' ? 'inherit' : '0'};
								margin-right: ${props =>
									props['data-rtl'] === 'rtl' ? '0' : 'inherit'};
							}
						}
					}
					.currencySignWithTotal {
						width: 300px;
						display: flex;
						justify-content: ${props =>
							props['data-rtl'] === 'rtl' ? 'flex-end' : 'flex-start'};
						margin-top: 15px;
						.grandTotalSpan {
							width: 50%;
							font-size: 18px;
							font-weight: 500;
							color: rgba(0, 0, 0, 0.85);
						}
						.currencySignWrap {
							width: 50%;
							.currencySign {
								margin-left: ${props =>
									props['data-rtl'] === 'rtl' ? 'inherit' : '0'};
								margin-right: ${props =>
									props['data-rtl'] === 'rtl' ? '0' : 'inherit'};
								width: 36px;
							}
							.currencySignSpan {
								margin-left: ${props =>
									props['data-rtl'] === 'rtl' ? 'inherit' : '15px'};
								margin-right: ${props =>
									props['data-rtl'] === 'rtl' ? '15px' : 'inherit'};
							}
						}
					}
				}
			}
		}

		.ButtonWrapper {
			width: 100%;
			display: flex;
			justify-content: ${props =>
				props['data-rtl'] === 'rtl' ? 'flex-start' : 'flex-end'};
			margin-top: 30px;
		}
		.mateInvoPrint {
			background: ${palette('blue', 14)};
			margin-left: ${props =>
				props['data-rtl'] === 'rtl' ? 'inherit' : '15px'};
			margin-right: ${props =>
				props['data-rtl'] === 'rtl' ? '15px' : 'inherit'};
		}
	}
`;

export default WithDirection(InvoicePageWrapper);
