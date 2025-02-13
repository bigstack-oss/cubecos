import styled from 'styled-components';
import { palette } from 'styled-theme';
import { transition } from '../../../config/style-util';
import WithDirection from '../../../config/withDirection';

const TagStyleWrapper = styled.div`
	display: inline-block;
	.ant-tag {
		display: inline-block;
		line-height: 24px;
		height: 26px;
		padding: 0 10px;
		border-radius: 4px;
		border: 1px solid ${palette('border', 0)};
		background: ${palette('grayscale', 6)};
		font-size: 12px;
		color: ${palette('text', 3)};
		opacity: 1;
		margin-top: 4px;
		margin-bottom: 4px;
		margin-right: ${props => (props['data-rtl'] === 'rtl' ? 'inherit' : '8px')};
		margin-left: ${props => (props['data-rtl'] === 'rtl' ? '8px' : 'inherit')};
		cursor: pointer;
		white-space: nowrap;
		${transition()};

		a {
			color: ${palette('text', 3)};

			&:hover {
				color: ${palette('text', 3)};
			}
		}

		.anticon-cross {
			margin: ${props =>
				props['data-rtl'] === 'rtl' ? '0 3px 0 0' : '0 0 0 3px'};
		}

		&.ant-tag-has-color {
			line-height: 24px;
			color: #ffffff;
			border: 0;
		}

		&.ant-tag-checkable {
			background-color: transparent;
			border-color: transparent;
			&:hover {
				color: ${palette('primary', 0)};
				background-color: transparent;
			}

			&:not(.ant-tag-checkable-checked) {
				&:hover {
					background-color: ${palette('primary', 0)};
					color: #ffffff;
				}
			}

			&:active {
				background-color: ${palette('primary', 0)};
				color: #ffffff;
			}

			&.ant-tag-checkable-checked {
				background-color: ${palette('primary', 0)};
				color: #ffffff;
			}
		}
	}
`;

export default WithDirection(TagStyleWrapper);
