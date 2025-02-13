import styled from 'styled-components';
import { palette } from 'styled-theme';
import WithDirection from '../../config/withDirection';

const bgImage = '/static/image/work.jpg';

const SignUpStyleWrapper = styled.div`
	width: 100%;
	min-height: 100vh;

	display: flex;
	justify-content: flex-end;
	align-items: center;
	position: relative;
	background: url(${bgImage}) no-repeat center center;
	background-size: cover;

	&:before {
		content: '';
		width: 100%;
		height: 100%;
		display: flex;
		background-color: rgba(0, 0, 0, 0.6);
		position: absolute;
		z-index: 1;
		top: 0;
		left: ${props => (props['data-rtl'] === 'rtl' ? 'inherit' : '0')};
		right: ${props => (props['data-rtl'] === 'rtl' ? '0' : 'inherit')};
	}

	.isoSignUpContentWrapper {
		width: 500px;
		height: 100%;
		overflow-y: auto;
		z-index: 10;
		position: relative;
	}

	.isoSignUpContent {
		min-height: 100%;
		display: flex;
		flex-direction: column;
		padding: 70px 50px;
		position: relative;
		background-color: #ffffff;

		@media only screen and (max-width: 767px) {
			width: 100%;
			padding: 70px 20px;
		}

		.isoLogoWrapper {
			width: 100%;
			display: flex;
			margin-bottom: 50px;
			justify-content: center;
			flex-shrink: 0;

			a,
			span {
				font-size: 24px;
				font-weight: 300;
				line-height: 1;
				text-transform: uppercase;
				color: ${palette('secondary', 2)};
			}
		}

		.isoSignUpForm {
			width: 100%;
			flex-shrink: 0;
			display: flex;
			flex-direction: column;

			.isoInputWrapper {
				margin-bottom: 15px;

				&:last-child {
					margin-bottom: 0;
				}

				input {
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
			}

			.isoLeftRightComponent {
				display: -webkit-box;
				display: -webkit-flex;
				display: -ms-flexbox;
				display: flex;
				-webkit-align-items: center;
				-webkit-box-align: center;
				-ms-flex-align: center;
				align-items: center;
				-webkit-box-pack: justify;
				-webkit-justify-content: space-between;
				-ms-flex-pack: justify;
				justify-content: space-between;
				width: 100%;
				input {
					width: calc(100% - 10px);

					&:first-child {
						margin-right: ${props =>
							props['data-rtl'] === 'rtl' ? 'inherit' : '20px'};
						margin-left: ${props =>
							props['data-rtl'] === 'rtl' ? '20px' : 'inherit'};
					}
				}
			}

			.isoHelperWrapper {
				margin-top: 35px;
				flex-direction: column;
			}

			.isoForgotPass {
				font-size: 12px;
				color: ${palette('text', 2)};
				margin-bottom: 10px;

				&:hover {
					color: ${palette('primary', 0)};
				}
			}

			button {
				font-weight: 500;
				width: 100%;
				height: 42px;
				border: 0;

				&.btnFacebook {
					background-color: ${palette('color', 7)};

					&:hover {
						background-color: ${palette('color', 8)};
					}
				}

				&.btnGooglePlus {
					background-color: ${palette('color', 9)};
					margin-top: 15px;

					&:hover {
						background-color: ${palette('color', 10)};
					}
				}

				&.btnAuthZero {
					background-color: ${palette('color', 11)};
					margin-top: 15px;

					&:hover {
						background-color: ${palette('color', 12)};
					}
				}

				&.btnFirebase {
					background-color: ${palette('color', 5)};
					margin-top: 15px;

					&:hover {
						background-color: ${palette('color', 6)};
					}
				}
			}
		}
	}
`;

export default WithDirection(SignUpStyleWrapper);
