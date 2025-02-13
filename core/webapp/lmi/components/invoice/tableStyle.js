import styled from 'styled-components';
import { palette } from 'styled-theme';
import Tables from '../uielements/table';
import { transition } from '../../config/style-util.js';

const Table = styled(Tables)`
	overflow: hidden;
	overflow-x: auto;
	background-color: #ffffff;

	.ant-table-thead > tr > th {
		color: ${palette('secondary', 2)};
		font-size: 13px;
		background-color: ${palette('secondary', 1)};
		border-bottom: 0;

		&.ant-table-column-sort {
			background: ${palette('secondary', 1)};
			margin: ${props =>
				props['data-rtl'] === 'rtl' ? '0 4px 0 0' : '0 0 0 4px'};
		}
	}

	.ant-table-thead > tr > th,
	.ant-table-tbody > tr > td {
		padding: 16px 15px;
		white-space: nowrap;
		text-align: ${props => (props['data-rtl'] === 'rtl' ? 'right' : 'left')};

		p {
			margin-bottom: 0;
		}

		&:first-child {
			text-align: center;
		}
	}

	.ant-table-tbody > tr > td {
		font-size: 12px;
		color: ${palette('text', 3)};
		border-bottom: 1px solid ${palette('border', 0)};

		a {
			color: ${palette('primary', 0)};
			${transition()};

			&:hover {
				color: ${palette('primary', 4)};
			}
		}
	}

	.ant-table-thead > tr.ant-table-row-hover > td,
	.ant-table-tbody > tr.ant-table-row-hover > td,
	.ant-table-thead > tr:hover > td,
	.ant-table-tbody > tr:hover > td {
		background-color: transparent;
	}
`;
export default Table;
