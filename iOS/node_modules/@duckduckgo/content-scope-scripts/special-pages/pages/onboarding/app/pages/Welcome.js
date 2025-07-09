import { h } from 'preact';
import { Button } from '../components/Buttons';
import { SlideUp } from '../components/Icons';
import { useTypedTranslation } from '../types';

/**
 * Renders the first page of the application and provides an option to move to the next page.
 *
 * @param {Object} props - The component props.
 * @param {() => void} props.onNextPage - Callback function to be called when the "Get Started" button is clicked.
 */
export function GetStarted({ onNextPage }) {
    const { t } = useTypedTranslation();

    return (
        <SlideUp>
            <Button onClick={onNextPage} size={'xl'}>
                {t('getStartedButton')}
            </Button>
        </SlideUp>
    );
}
