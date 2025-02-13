import styled from 'styled-components';
import { palette } from 'styled-theme';
import { transition, borderRadius } from '../../../../config/style-util';

const LeafletMapWrapper = styled.div`
	&.isoLeafletMap {
		.leaflet-top,
		.leaflet-bottom {
			z-index: 400;
		}

		.leaflet-control-zoom {
			border: 0;
			user-select: none;
			border-radius: 2px;
			cursor: pointer;
			background-color: rgb(255, 255, 255);
			width: 28px;
			height: 55px;
			.isoBoxShadow(rgba(0, 0, 0, 0.3) 0px 1px 4px -1px);
		}

		.leaflet-bar {
			a {
				background-color: #ffffff;
				border-bottom: 1px solid rgb(230, 230, 230);
				font-size: @isoFontSize + 4;
				line-height: 27px;
				color: ${palette('text', 3)};
				${transition()};

				&:hover {
					color: ${palette('primary', 0)};
				}
			}
		}

		.leaflet-popup {
			margin-bottom: 10px;
		}

		.leaflet-popup-close-button {
			width: 24px;
			height: 24px;
			display: -webkit-inline-flex;
			display: -ms-inline-flex;
			display: inline-flex;
			align-items: center;
			justify-content: center;
			background-color: rgba(0, 0, 0, 0.2);
			border: 0;
			outline: 0;
			padding: 0;
			text-align: center;
			cursor: pointer;
			position: absolute;
			top: 0;
			right: 0;
			font-size: 0;
			${transition()};

			&:before {
				content: '\f2d7';
				font-family: 'ionicons';
				width: 100%;
				font-size: 14px;
				color: #fff;
				${transition()};
			}

			&:hover {
				background-color: rgba(255, 255, 255, 0.25);
			}
		}

		.leaflet-popup-close-button
			+ .leaflet-popup-content-wrapper
			.leaflet-popup-content {
			padding-top: 0;
		}

		.leaflet-popup-tip-container {
			width: 40px;
			height: 20px;
			position: absolute;
			left: 50%;
			margin-left: -20px;
			pointer-events: none;
			overflow: hidden;

			.leaflet-popup-tip {
				width: 17px;
				height: 17px;
				transform: rotate(45deg);
				padding: 1px;
				margin: -10px auto 0px;
			}
		}

		.leaflet-popup-content-wrapper {
			${borderRadius('0')};

			.leaflet-popup-content {
				position: relative;
				padding: 0;
				display: flex;
				flex-direction: column;
				margin: 0;
				min-width: 260px;

				.windowCloseBtn {
					svg {
						${transition()};
					}
				}

				.isoInfoWindowImage {
					width: 100%;
					height: 180px;
					overflow: hidden;
					text-align: center;
					position: relative;
					display: flex;

					img {
						width: 100%;
						height: 100%;
						object-fit: cover;
					}
				}

				.isoInfoWindowDetails {
					display: block;
					padding: 10px 30px;

					h3 {
						margin: 0;
						font-size: 14px;
						font-weight: 500;
						color: ${palette('text', 0)};
						text-align: center;

						a {
							font-family: inherit;
							font-size: inherit;
							font-weight: inherit;
							color: inherit;
							text-align: center;
						}
					}

					p {
						font-size: 13px;
						font-weight: 400;
						color: ${palette('text', 1)};
						margin-bottom: 0px;
						text-align: center;
					}
				}
			}
		}

		.marker-cluster {
			background-color: ${palette('primary', 4)} !important;

			> div {
				background-color: ${palette('primary', 6)} !important;

				span {
					color: #ffffff;
				}
			}
		}
	}

	.marker-icon {
		width: 44px !important;
		height: 44px !important;
		display: -webkit-inline-flex;
		display: -ms-inline-flex;
		display: inline-flex;
		align-items: center;
		justify-content: center;
		background-color: #ffffff;
		border-radius: 50%;
		position: relative;
		${transition('0.4s')};

		.marker-icon-wrapper {
			width: 36px;
			height: 36px;
			display: -webkit-inline-flex;
			display: -ms-inline-flex;
			display: inline-flex;
			align-items: center;
			justify-content: center;
			background-color: ${palette('primary', 0)};
			border-radius: 50%;

			i {
				color: #fff;
				font-size: 19px;
				line-height: 1;
			}
		}
	}
`;

export default LeafletMapWrapper;
