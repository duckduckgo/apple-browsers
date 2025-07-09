import { h } from 'preact';
import cn from 'classnames';
import { useStepConfig } from './useStepConfig';
import { useGlobalDispatch } from '../../global';
import { Heading } from './Heading';
import { SingleLineProgress } from '../Progress';
import { ElasticButton } from './ElasticButton';
import { Stack } from '../Stack';
import { SlideIn } from './Animation';

import styles from './SingleStep.module.css';

/**
 * @param {object} props
 * @param {import('./data-types').Progress} props.progress
 * @param {import('preact').JSX.Element|null} [props.dismissButton]
 * @param {import('preact').JSX.Element|null} [props.acceptButton]
 * @param {import('preact').ComponentChild} [props.children]
 */
export function StepGrid({ progress, dismissButton, acceptButton, children }) {
    return (
        <div className={styles.container}>
            <div className={styles.content}>
                <Stack animate>{children}</Stack>
            </div>
            <div className={styles.progress}>
                <SingleLineProgress current={progress.current} total={progress.total} />
            </div>

            <div className={styles.buttonBar}>
                {(dismissButton || acceptButton) && (
                    <SlideIn>
                        <div class={styles.buttonBarContents}>
                            <div className={styles.dismiss}>{dismissButton}</div>

                            <div className={styles.accept}>{acceptButton}</div>
                        </div>
                    </SlideIn>
                )}
            </div>
        </div>
    );
}

export function SingleStep() {
    const dispatch = useGlobalDispatch();
    const { variant, heading, dismissButton, acceptButton, content, progress } = useStepConfig();

    const classes = cn({
        [styles.panel]: true,
        [styles.boxed]: variant === 'box',
    });

    const onTitleComplete = () => dispatch({ kind: 'title-complete' });

    return (
        <div className={classes}>
            <Stack animate>
                <div className={styles.heading}>
                    <Heading {...heading} onTitleComplete={onTitleComplete} />
                </div>

                {content && (
                    <StepGrid
                        progress={progress}
                        dismissButton={
                            dismissButton && (
                                <ElasticButton {...dismissButton} elastic={false} variant="secondary" onClick={dismissButton.handler} />
                            )
                        }
                        acceptButton={
                            acceptButton && (
                                <ElasticButton {...acceptButton} elastic={true} variant="primary" onClick={acceptButton.handler} />
                            )
                        }
                    >
                        {content}
                    </StepGrid>
                )}
            </Stack>
        </div>
    );
}
