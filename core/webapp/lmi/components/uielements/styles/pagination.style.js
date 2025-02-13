import styled from 'styled-components';
import { palette } from 'styled-theme';
import { transition } from '../../../config/style-util';

const Pagination = ComponentName => styled(ComponentName)`
	&.ant-pagination {
		.ant-pagination-item {
			margin: ${props =>
				props['data-rtl'] === 'rtl' ? '0 0 0 8px' : '0 8px 0 0'};
			&.ant-pagination-item-active {
				background-color: ${palette('primary', 0)};
				border-color: ${palette('primary', 0)};

				&:hover {
					background-color: ${palette('primary', 4)};
					a {
						color: #ffffff;
					}
				}
			}

			&:hover {
				border-color: ${palette('primary', 0)};
				${transition()};
			}

			&:hover a {
				color: ${palette('primary', 0)};
			}
		}

		.ant-pagination-total-text {
			margin: ${props =>
				props['data-rtl'] === 'rtl' ? '0 0 0 8px' : '0 8px 0 0'};
		}

		.ant-pagination-prev,
		.ant-pagination-jump-prev,
		.ant-pagination-jump-next {
			margin: ${props =>
				props['data-rtl'] === 'rtl' ? '0 0 0 8px' : '0 8px 0 0'};
		}

		.ant-pagination-prev:hover,
		.ant-pagination-next:hover {
			border-color: ${palette('primary', 0)};

			a {
				color: ${palette('primary', 0)};
			}
		}

		.ant-pagination-prev .ant-pagination-item-link,
		.ant-pagination-next .ant-pagination-item-link {
			transform: ${props =>
				props['data-rtl'] === 'rtl' ? 'rotate(180deg)' : 'rotate(0)'};
		}

		.ant-pagination-jump-prev,
		.ant-pagination-jump-next {
			&:after {
				transform: ${props =>
					props['data-rtl'] === 'rtl'
						? 'rotate(180deg) scale(0.66666667)'
						: 'rotate(0) scale(0.66666667)'};
			}
		}

		&.ant-pagination-simple {
			.ant-pagination-prev,
			.ant-pagination-next {
				margin: 0;
			}

			.ant-pagination-simple-pager {
				margin: ${props =>
					props['data-rtl'] === 'rtl' ? '0 0 0 8px' : '0 8px 0 0'};
			}
		}

		.ant-pagination-options {
			margin: ${props =>
				props['data-rtl'] === 'rtl' ? '0 10px 0 0' : '0 0 0 10px'};

			.ant-select .ant-select-selection.ant-select-selection--single {
				height: 28px;

				.ant-select-selection__rendered {
					line-height: 28px;
				}
			}

			.ant-pagination-options-size-changer {
				margin: ${props =>
					props['data-rtl'] === 'rtl' ? '0 0 0 8px' : '0 8px 0 0'};
			}
		}
		.ant-pagination-options-quick-jumper {
			margin-top: 5px;
		}
	}
`;

export default Pagination;
