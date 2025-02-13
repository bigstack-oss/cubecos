import styled from 'styled-components';
import { palette } from 'styled-theme';
import WithDirection from '../../config/withDirection';

const CardWrapper = styled.div`
	width: auto;
	overflow: inherit;
	position: relative;
	.isoInvoiceTable {
		table {
			tbody {
				tr {
					td {
						.isoInvoiceBtnView {
							display: flex;
							flex-direction: row;
							opacity: 0;
							> a,
							button {
								margin: ${props =>
									props['data-rtl'] === 'rtl' ? '0 0 0 15px' : '0 15px 0 0'};
							}
						}
					}
					&:hover {
						.isoInvoiceBtnView {
							opacity: 1;
						}
					}
				}
			}
		}
	}
	.isoInvoiceTableBtn {
		display: flex;
		margin-top: 20px;
		a {
			margin-left: auto;
		}
	}

	.invoiceListTable {
		.ant-dropdown-menu-item,
		.ant-dropdown-menu-submenu-title {
			&:hover {
				background-color: ${palette('secondary', 1)};
			}
		}

		.invoiceViewBtn {
			color: ${palette('text', 3)};

			&:hover {
				color: ${palette('primary', 0)};
			}
		}

		.invoiceDltBtn {
			border: 0;
			color: ${palette('text', 1)};

			&:hover {
				border: 0;
				color: ${palette('primary', 0)};
			}
		}
	}
`;

export default WithDirection(CardWrapper);
