import styled from 'styled-components';
import { palette, font } from 'styled-theme';
import { transition, borderRadius, boxShadow } from '../../config/style-util';
import WithDirection from '../../config/withDirection';

const WDSidebarWrapper = styled.div`
	width: 340px;
	display: flex;
	flex-direction: column;
	flex-shrink: 0;
	margin: ${props =>
		props['data-rtl'] === 'rtl' ? '0 0 0 30px' : '0 30px 0 0'};
	${transition()};

	@media only screen and (max-width: 767px) {
		width: 100%;
		margin-left: ${props =>
			props['data-rtl'] === 'rtl' ? '30px' : 'calc(-100% + -30px)'};
		margin-right: ${props =>
			props['data-rtl'] === 'rtl' ? 'calc(-100% + -30px)' : '30px'};
	}

	@media only screen and (min-width: 768px) and (max-width: 1199px) {
		width: 270px;
	}

	.ais-SearchBox__root {
		width: 100%;
		margin-bottom: 15px;
		max-width: 100%;

		.ais-SearchBox__input {
			padding: ${props =>
				props['data-rtl'] === 'rtl' ? '0 46px 0 36px' : '0 36px 0 46px'};
			border: 1px solid ${palette('border', 0)};
			${borderRadius('3px')};
			${boxShadow()};
		}

		.ais-SearchBox__submit {
			right: ${props => (props['data-rtl'] === 'rtl' ? '0' : 'inherit')};
			left: ${props => (props['data-rtl'] === 'rtl' ? 'inherit' : '0')};
		}
	}

	.isoAlgoliaSidebarItem {
		width: 100%;
		display: flex;
		flex-direction: column;
		padding: 15px 25px;
		margin-bottom: 15px;
		background-color: #ffffff;
		border: 1px solid ${palette('border', 0)};
		${borderRadius('3px')};

		.isoAlgoliaSidebarTitle {
			font-size: 14px;
			font-weight: 700;
			color: ${palette('text', 0)};
			line-height: 1.3;
			margin: 0 0 20px;
			display: flex;
		}

		&.isoInline {
			flex-direction: row;
			align-items: center;
			justify-content: space-between;

			.isoAlgoliaSidebarTitle {
				margin-bottom: 0;
			}
		}

		/* Radio */
		.ais-MultiRange__root {
			.ais-MultiRange__item {
				line-height: 1;
				margin-top: 10px;

				&:first-child {
					margin-top: 0;
				}

				label {
					align-items: center;
				}

				.ais-MultiRange__itemBox {
					margin: ${props =>
						props['data-rtl'] === 'rtl' ? '0 0 0 8px' : '0 8px 0 0'};
				}
			}
		}

		/* rating */
		.ais-StarRating__root {
			.ais-StarRating__ratingLink {
				display: flex;
				align-items: center;
				text-decoration: none;

				&:first-child {
					margin-top: 0;
				}

				.ais-StarRating__ratingLabel {
					margin: ${props =>
						props['data-rtl'] === 'rtl' ? '0 10px 0 0' : '0 0 0 10px'};
				}

				.ais-StarRating__ratingCount {
					margin: ${props =>
						props['data-rtl'] === 'rtl' ? '0 auto 0 0' : '0 0 0 auto'};
				}
			}
		}

		/* Range Slider */
		.isoAlRangeSlider {
			width: 100%;
			display: flex;
			flex-direction: column;
			margin-top: -25px;

			.isoAlRangeNumber {
				display: flex;
				justify-content: flex-end;
				margin-bottom: 15px;

				span {
					font-size: 13px;
					font-weight: 400;
					color: ${palette('text', 3)};
					line-height: 1.3;
					padding: ${props =>
						props['data-rtl'] === 'rtl' ? '0 0 0 10px' : '0 10px 0 0'};

					&:last-child {
						padding: ${props =>
							props['data-rtl'] === 'rtl' ? '0 10px 0 0' : '0 0 0 10px'};
					}
				}
			}

			.rheostat-horizontal {
				height: 15px;

				.rheostat-background {
					width: 100%;
					height: 6px;
					background-color: ${palette('secondary', 1)};
					display: flex;
					margin-top: 4px;
				}

				.rheostat-progress {
					position: absolute;
					top: 4px;
					height: 6px;
					background-color: ${palette('primary', 9)};
				}

				button {
					width: 14px;
					height: 14px;
					border-radius: 50%;
					background-color: ${palette('primary', 9)};
					border: 0px;
					outline: 0px;
					top: 0;
					margin-left: -5px;
					z-index: 1;

					&::before {
						content: '';
						width: 6px;
						height: 6px;
						display: flex;
						border-radius: 50%;
						background-color: #fff;
						position: absolute;
						top: 4px;
						left: 4px;
					}
				}
			}
		}

		/* Checkbox */
		.ais-RefinementList__root {
			.ais-RefinementList__SearchBox {
				.ais-SearchBox__root {
					margin-bottom: 10px;
				}
			}

			.ais-RefinementList__item {
				&:first-child {
					margin-top: 0;
				}

				label {
					display: flex;
					align-items: center;
					font-size: 13px;
					color: ${palette('text', 1)};

					.ais-RefinementList__itemCount {
						margin: ${props =>
							props['data-rtl'] === 'rtl' ? ' 0 auto 0 0' : '0 0 0 auto'};
					}

					.ais-RefinementList__itemBox {
						margin: ${props =>
							props['data-rtl'] === 'rtl' ? '0 0 0 8px' : '0 8px 0 0'};
					}
				}
			}
		}

		/* Hirarchi */
		.ais-HierarchicalMenu__root {
			.ais-HierarchicalMenu__item {
				margin-top: 8px;
				float: ${props => (props['data-rtl'] === 'rtl' ? 'right' : 'left')};

				&:after {
					right: ${props =>
						props['data-rtl'] === 'rtl' ? 'inherit' : '-22px'};
					left: ${props => (props['data-rtl'] === 'rtl' ? '-22px' : 'inherit')};
					transform: ${props =>
						props['data-rtl'] === 'rtl'
							? 'translateY(-50%) rotate(180deg)'
							: 'translateY(-50%) rotate(0deg)'};
				}

				&:first-child {
					margin-top: 0;
				}

				.ais-HierarchicalMenu__itemLink {
					&:focus {
						text-decoration: none;
					}
				}

				&.ais-HierarchicalMenu__itemParent {
					.ais-HierarchicalMenu__item {
						margin-top: 8px;
					}
				}
			}
		}
	}

	.ais-ClearAll__root {
		padding: 12px 8px;
		display: block;
		font-weight: 700;
		text-transform: uppercase;

		@media only screen and (max-width: 358px) {
			margin-top: 10px;
		}
	}
`;

const WDContentWrapper = styled.div`
	width: calc(100% - 370px);
	display: flex;
	flex-direction: column;

	@media only screen and (max-width: 767px) {
		width: 100%;
		margin-right: ${props => (props['data-rtl'] === 'rtl' ? '30px' : '0')};
	}

	@media only screen and (min-width: 768px) and (max-width: 1199px) {
		width: calc(100% - 300px);
	}

	.ais-Hits__root {
		width: 100%;
		display: flex;
		flex-wrap: wrap;
	}

	&.list {
		.ais-Hits__root {
			flex-direction: column;
		}
	}
`;

const WDGridListViewWrapper = styled.div`
	&.GridView {
		width: calc(100% / 2 - 10px);
		display: -webkit-box;
		display: -moz-box;
		display: -ms-flexbox;
		display: -webkit-flex;
		display: flex;
		flex-direction: column;
		padding: 0;
		background-color: #fff;
		margin: ${props =>
			props['data-rtl'] === 'rtl' ? '0 0 20px 20px' : '0 20px 20px 0'};
		position: relative;
		border: 1px solid ${palette('border', 0)};

		&:nth-child(2n) {
			margin: ${props =>
				props['data-rtl'] === 'rtl' ? '0 0 20px 0' : '0 0 20px 0'};
		}

		@media only screen and (min-width: 1400px) {
			width: calc(100% / 3 - 14px);

			&:nth-child(2n) {
				margin: ${props =>
					props['data-rtl'] === 'rtl' ? '0 0 20px 20px' : '0 20px 20px 0'};
			}

			&:nth-child(3n) {
				margin: ${props =>
					props['data-rtl'] === 'rtl' ? '0 0 20px' : '0 0 20px'};
			}
		}

		@media only screen and (max-width: 550px) {
			width: 100%;
			margin: 0 0 20px;
		}

		@media only screen and (min-width: 768px) and (max-width: 991px) {
			width: 100%;
			flex-shrink: 0;
		}

		.isoAlGridImage {
			width: 100%;
			height: 260px;
			display: -webkit-box;
			display: -moz-box;
			display: -ms-flexbox;
			display: -webkit-flex;
			display: flex;
			flex-shrink: 0;
			align-items: center;
			-webkit-align-items: center;
			justify-content: center;
			-webkit-justify-content: center;
			overflow: hidden;
			background-color: ${palette('grayscale', 5)};
			position: relative;

			&:after {
				content: '';
				width: 100%;
				height: 100%;
				display: flex;
				background-color: rgba(0, 0, 0, 0.6);
				position: absolute;
				top: 0;
				left: 0;
				opacity: 0;
				${transition()};
			}

			.ant-btn {
				&.isoAlAddToCart {
					background-color: #ffffff;
					border-color: #ffffff !important;
					color: ${palette('text', 0)};
					z-index: 1;
					position: absolute;
					height: 42px;
					opacity: 0;
					padding: 0 20px;
					transform: scale(0.8);
					${transition()};

					i {
						margin: ${props =>
							props['data-rtl'] === 'rtl' ? '0 0 0 10px' : '0 10px 0 0'};
						font-size: 14px;
					}

					&:hover {
						background-color: ${palette('grayscale', 4)};
					}

					&.ant-btn-loading {
						i:not(.anticon-loading) {
							margin: ${props =>
								props['data-rtl'] === 'rtl' ? '0 10px 0 0' : '0 0 0 10px'};
						}
					}
				}
			}

			img {
				max-width: 100%;
			}

			@media only screen and (max-width: 991px) {
				width: 100%;
				overflow: hidden;
			}
		}

		.isoAlGridContents {
			width: 100%;
			padding: 20px 25px;
			display: -webkit-box;
			display: -moz-box;
			display: -ms-flexbox;
			display: -webkit-flex;
			display: flex;
			flex-direction: column;

			@media only screen and (max-width: 991px) {
				margin-top: 15px;
			}

			.isoAlGridName {
				text-overflow: ellipsis;
				overflow: hidden;
				white-space: nowrap;
				margin-bottom: 5px;

				.ais-Highlight__nonHighlighted {
					font-size: 14px;
					font-weight: 700;
					color: ${palette('text', 0)};
					line-height: 1.3;
				}
			}

			.isoAlGridPriceRating {
				display: flex;
				align-items: center;

				.isoAlGridPrice {
					font-size: 14px;
					font-weight: 400;
					color: #ffffff;
					padding: 5px 10px;
					line-height: 1;
					position: absolute;
					top: 30px;
					right: 0px;
					background-color: ${palette('primary', 9)};
					${borderRadius('3px 0 0 3px')};
				}

				.isoAlGridRating {
					display: none;
					.ant-rate {
						display: flex;
						.ant-rate-star {
							font-size: 9px;
							margin-right: 2px;
						}
					}
				}
			}

			.isoAlGridDescription {
				display: none;

				.ais-Highlight__nonHighlighted {
					font-size: 13px;
					font-weight: 400;
					color: ${palette('text', 2)};
					line-height: 1.5;
				}
			}
		}

		&:hover {
			.isoAlGridImage {
				&:after {
					opacity: 1;
				}

				.isoAlAddToCart {
					opacity: 1;
					transform: scale(1);
				}
			}
		}
	}

	&.ListView {
		width: 100%;
		display: flex;
		padding: 10px;
		background-color: #fff;
		margin-bottom: 15px;
		border: 1px solid ${palette('border', 0)};

		@media only screen and (max-width: 991px) {
			flex-direction: column;
		}

		.isoAlGridImage {
			width: 240px;
			height: auto;
			display: flex;
			flex-shrink: 0;
			align-items: center;
			justify-content: center;
			overflow: hidden;
			position: relative;

			&:after {
				content: '';
				width: 100%;
				height: 100%;
				display: flex;
				background-color: rgba(0, 0, 0, 0.6);
				position: absolute;
				top: 0;
				left: 0;
				opacity: 0;
				${transition()};
			}

			.isoAlAddToCart {
				background-color: #ffffff;
				border-color: #ffffff !important;
				color: ${palette('text', 0)};
				z-index: 1;
				position: absolute;
				height: 42px;
				opacity: 0;
				padding: 0 20px;
				direction: ${props => (props['data-rtl'] === 'rtl' ? 'rtl' : 'ltr')};
				transform: scale(0.8);
				${transition()};

				i {
					margin: ${props =>
						props['data-rtl'] === 'rtl' ? '0 0 0 10px' : '0 10px 0 0'};
					font-size: 14px;
				}

				&:hover {
					background-color: ${palette('grayscale', 4)};
				}
			}

			&:hover {
				&:after {
					opacity: 1;
				}

				.isoAlAddToCart {
					opacity: 1;
					transform: scale(1);
				}
			}

			img {
				max-width: 100%;
			}

			@media only screen and (max-width: 991px) {
				width: 100%;
				height: auto;
				overflow: hidden;
			}
		}

		.isoAlGridContents {
			width: 100%;
			padding: 30px 15px;
			padding-left: 30px;
			display: flex;
			flex-direction: column;

			@media only screen and (max-width: 991px) {
				margin-top: 15px;
			}

			.isoAlGridName {
				.ais-Highlight__nonHighlighted {
					font-size: 16px;
					font-weight: 700;
					color: ${palette('text', 0)};
					line-height: 1.3;
					margin-bottom: 10px;
					display: flex;
				}
			}

			.isoAlGridPriceRating {
				display: flex;
				justify-content: space-between;
				align-items: center;
				margin-bottom: 20px;

				.isoAlGridPrice {
					font-size: 14px;
					font-weight: 400;
					color: ${palette('text', 0)};
					line-height: 1;
				}

				.isoAlGridRating {
					.ant-rate {
						display: flex;
						.ant-rate-star {
							font-size: 9px;
							margin-right: 2px;
						}
					}
				}
			}

			.isoAlGridDescription {
				.ais-Highlight__nonHighlighted {
					font-size: 13px;
					font-weight: 400;
					color: ${palette('text', 2)};
					line-height: 1.5;
				}
			}
		}
	}
`;

const WDTopbarWrapper = styled.div`
	width: 100%;
	display: flex;
	align-items: center;
	margin-bottom: 27px;
	flex-wrap: wrap;

	.ais-Stats__root {
		font-size: 14px;
		font-weight: 500;
		color: ${palette('text', 0)};

		@media only screen and (max-width: 991px) {
			width: 100%;
			margin-bottom: 15px;
		}
	}

	.ais-SortBy__root {
		margin-left: ${props => (props['data-rtl'] === 'rtl' ? '20px' : 'auto')};
		margin-right: ${props => (props['data-rtl'] === 'rtl' ? 'auto' : '20px')};
		border: 1px solid ${palette('border', 0)};
		&:focus {
			background-color: #ffffff;
		}

		@media only screen and (max-width: 991px) {
			margin: ${props =>
				props['data-rtl'] === 'rtl' ? '0 0 0 auto' : '0 auto 0 0'};
		}
	}

	.isoViewChanger {
		display: flex;
		align-items: center;

		button {
			font-size: 16px;
			text-align: center;
			width: 35px;
			height: 35px;
			display: flex;
			color: ${palette('secondary', 0)};
			align-items: center;
			justify-content: center;
			background-color: #ffffff;
			outline: 0;
			margin-left: -1px;
			border: 1px solid ${palette('border', 0)};
			cursor: pointer;
			${transition()};

			i {
				font-size: 18px;
				width: 100%;
				line-height: 33px;
				color: ${palette('secondary', 0)};
				${transition()};
			}

			&.active {
				background-color: ${palette('primary', 9)};
				border-color: ${palette('primary', 9)};
				i {
					color: #ffffff;
				}
			}

			&:first-child {
				margin-left: 0;
			}

			&:hover {
				color: #ffffff;
				background-color: #265cda;
				border-color: #265cda;

				i {
					color: #ffffff;
				}
			}
		}
	}
`;

const WDVoiceSearchWrapper = styled.div`
	width: 100%;
	padding: 10px 15px;
	display: flex;
	background-color: #ffffff;
	margin-bottom: 15px;
	border: 1px solid ${palette('border', 0)};
	${borderRadius('3px')};

	div {
		width: 100%;
		display: flex;
		align-items: center;
	}

	button {
		width: 30px;
		height: 30px;
		display: flex;
		align-items: center;
		justify-content: center;
		flex-shrink: 0;
		position: relative;
		outline: 0;
		cursor: pointer;
		background-color: transparent;
		${transition()};
		${borderRadius('50%')};

		&:before {
			content: '';
			font-size: 17px;
			font-family: 'ionicons';
			-webkit-transition: color 0.3s cubic-bezier(0.215, 0.61, 0.355, 1);
			-moz-transition: color 0.3s cubic-bezier(0.215, 0.61, 0.355, 1);
			-ms-transition: color 0.3s cubic-bezier(0.215, 0.61, 0.355, 1);
			-o-transition: color 0.3s cubic-bezier(0.215, 0.61, 0.355, 1);
			transition: color 0.3s cubic-bezier(0.215, 0.61, 0.355, 1);
		}

		&:hover {
			&:before {
			}
		}
	}

	span {
		font-size: 14px;
		font-weight: 400;
		line-height: 1.4;
	}

	.isoVoiceSearchStart {
		button {
			&:before {
				content: '\f2ec';
			}
		}
	}

	.isoVoiceSearchRunning {
		button {
			&:before {
				content: '\f24f';
				font-size: 13px;
			}
		}
	}
`;

const WDFooterWrapper = styled.footer`
	display: flex;
	width: 100%;
	align-items: center;
	justify-content: flex-end;
	margin-top: 40px;

	span {
		font-size: 14px;
		font-weight: 700;
		line-height: 1.3;
	}

	.isoLogoWrapper {
		max-width: 150px;

		img {
			max-width: 100%;
		}
	}
`;

const LoaderElement = styled.div`
	width: 100%;
	height: 80vh;
	display: flex;
	align-items: center;
	justify-content: center;

	.loaderElement {
		height: 3em;
		width: 3em;
		animation: rotation 1s infinite linear;
		border: 2px solid rgba(51, 105, 231, 0.3);
		border-top-color: rgb(51, 105, 231);
		border-radius: 50%;
	}

	@keyframes rotation {
		to {
			transform: rotate(360deg);
		}
	}
`;

const PaginationStyleWrapper = styled.div`
	.ais-Pagination__root {
		display: flex;
		align-items: center;
		justify-content: center;
		flex-wrap: wrap;
		padding: 8px 16px;
		${borderRadius('3px')};
		${boxShadow()};

		.ais-Pagination__item {
			padding: 3px;

			&.ais-Pagination__itemSelected {
				&:hover {
					a {
						color: #ffffff;
					}
				}
			}

			a {
				text-decoration: none;
			}
		}
	}
`;

const SidebarWrapper = WithDirection(WDSidebarWrapper);
const ContentWrapper = WithDirection(WDContentWrapper);
const VoiceSearchWrapper = WithDirection(WDVoiceSearchWrapper);
const GridListViewWrapper = WithDirection(WDGridListViewWrapper);
const TopbarWrapper = WithDirection(WDTopbarWrapper);
const FooterWrapper = WithDirection(WDFooterWrapper);

export {
	SidebarWrapper,
	ContentWrapper,
	FooterWrapper,
	GridListViewWrapper,
	VoiceSearchWrapper,
	LoaderElement,
	TopbarWrapper,
	PaginationStyleWrapper,
};
