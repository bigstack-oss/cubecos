import styled from 'styled-components';
import { palette } from 'styled-theme';
import { boxShadow, borderRadius, transition } from '../../config/style-util';
import WithDirection from '../../config/withDirection';

const MailBox = styled.div`
	width: 100%;
	height: calc(100vh - 137px);
	display: flex;

	@media only screen and (max-width: 767px) {
		height: calc(100vh - 110px);
	}

	.isoLeftWrapper {
		display: flex;
		flex-shrink: 0;
		flex-direction: column;
		background-color: #ffffff;
		width: 250px;
		border-right: ${props => (props['data-rtl'] === 'rtl' ? 0 : 1)}px solid
			${palette('border', 4)};
		border-left: ${props => (props['data-rtl'] === 'rtl' ? 1 : 0)}px solid
			${palette('border', 4)};

		.isoMailOptions {
			width: 100%;
			display: flex;
			flex-direction: column;
			height: 100%;
			overflow-y: auto;
		}
	}

	.isoMiddleWrapper {
		display: flex;
		flex-direction: column;
		flex-shrink: 0;
		background-color: #ffffff;
		border-right: ${props => (props['data-rtl'] === 'rtl' ? 0 : 1)}px solid
			${palette('border', 4)};
		border-left: ${props => (props['data-rtl'] === 'rtl' ? 1 : 0)}px solid
			${palette('border', 4)};
		width: 400px;

		@media only screen and (max-width: 767px) {
			width: 100%;
		}

		@media only screen and (min-width: 767px) and (max-width: 990px) {
			width: 320px;
		}

		@media only screen and (min-width: 991px) and (max-width: 1366px) {
			width: 340px;
		}

		.isoBucketLabel {
			width: 100%;
			height: 80px;
			display: flex;
			flex-shrink: 0;
			align-items: center;
			justify-content: space-between;
			padding: 0px 30px;
			background-color: ${palette('grayscale', 6)};
			border-bottom: 1px solid ${palette('border', 0)};

			h3 {
				font-size: 16px;
				font-weight: 500;
				text-transform: capitalize;
				color: ${palette('secondary', 2)};
				line-height: 1.1;
			}

			@media only screen and (max-width: 767px) {
				height: 60px;
				padding: 0 20px;
			}
		}

		.isoSearchMailWrapper {
			width: 100%;
			height: 40px;
			display: flex;
			flex-shrink: 0;
			align-items: center;
			justify-content: space-between;
			background-color: ${palette('grayscale', 6)};
			border-bottom: 1px solid ${palette('border', 0)};

			input {
				font-size: 14px;
				font-weight: 400;
				color: ${palette('text', 2)};
				line-height: inherit;
				height: 39px;
				width: 100%;
				padding: 0 30px;
				margin-bottom: 0;
				border: 0;
				outline: 0 !important;
				overflow: hidden;
				background-color: ${palette('grayscale', 6)};
				${borderRadius()};
				${boxShadow()};
				${transition()};

				&:focus,
				&:hover {
					border-color: transparent;
					${boxShadow()};
				}

				@media only screen and (max-width: 767px) {
					padding: 0 20px;
				}

				&::-webkit-input-placeholder {
					color: ${palette('grayscale', 0)};
				}

				&:-moz-placeholder {
					color: ${palette('grayscale', 0)};
				}

				&::-moz-placeholder {
					color: ${palette('grayscale', 0)};
				}
				&:-ms-input-placeholder {
					color: ${palette('grayscale', 0)};
				}
			}

			.ant-input-suffix {
				display: none;
			}
		}
	}

	.isoSingleMailWrapper {
		width: 100%;
		display: flex;
		flex-direction: column;
		background-color: #ffffff;

		.isoNoMailMsg {
			font-size: 28px;
			font-weight: 300;
			text-transform: capitalize;
			color: ${palette('text', 2)};
			text-align: center;
			width: 100%;
			height: 100%;
			display: flex;
			align-items: center;
			justify-content: center;
		}
	}

	.isoBackCatBtn {
		font-size: 14px;
		color: ${palette('secondary', 0)};
		height: 35px;
		padding: 0 15px;
		display: flex;
		align-items: center;
		justify-content: center;
		background-color: #ffffff;
		outline: 0;
		border: 1px solid ${palette('border', 0)};
		cursor: pointer;
		${transition()};

		i {
			font-size: 20px;
			color: ${palette('secondary', 0)};
			${transition()};
		}

		&:hover {
			color: ${palette('primary', 0)};
			background-color: #fcfcfc;

			i {
				color: ${palette('primary', 0)};
			}
		}
	}
`;

export default WithDirection(MailBox);
