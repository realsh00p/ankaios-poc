import { SolutionVersionSpec } from '../app/types';
import {Table, TableHeader, TableColumn, TableBody, TableRow, TableCell, Chip} from "@nextui-org/react";
import {FaDocker} from 'react-icons/fa';
import {SiHelm} from 'react-icons/si';
import {SiKubernetes} from 'react-icons/si';
import {SiWindows} from 'react-icons/si';
import { LuBinary } from 'react-icons/lu';
interface SolutionVersionSpecCardProps {
    solutionversion: SolutionVersionSpec;
}

function getProperty(component: any, name: string) {
    return component?.properties?.[name];
}

function getRuntimeConfigValue(component: any, name: string) {
    const runtimeConfig = getProperty(component, 'ankaios.runtimeConfig');
    if (typeof runtimeConfig !== 'string') {
        return undefined;
    }

    const prefix = `${name}:`;
    const line = runtimeConfig.split('\n').find((item) => item.trim().startsWith(prefix));
    return line?.trim().slice(prefix.length).trim();
}

function getImage(component: any) {
    return getProperty(component, 'container.image')
        ?? getRuntimeConfigValue(component, 'image')
        ?? getProperty(component, 'program.image')
        ?? getProperty(component, 'app.image')
        ?? '(unknown)';
}

function getImageName(image: string) {
    return image.includes(':') ? image.split(':').slice(0, -1).join(':') : image;
}

function getImageVersion(image: string) {
    return image.includes(':') ? image.split(':').pop() : '(latest)';
}

function SolutionVersionSpecCard(props: SolutionVersionSpecCardProps) {
    const { solutionversion } = props;
    return (
        <>
            <div className="components-label">Components</div>
            <Table removeWrapper>
                <TableHeader>
                    <TableColumn> </TableColumn>
                    <TableColumn>NAME</TableColumn>
                    <TableColumn>PACKAGE</TableColumn>
                    <TableColumn>VERSION</TableColumn>
                </TableHeader>
                <TableBody>
                    {solutionversion.components.map((component: any) => (
                        <TableRow key={component.name}>
                            <TableCell>
                                {component.type === 'container' && (
                                    <FaDocker className="text-[#AAAAF9] text-xl"/>
                                )}
                                {component.type === 'helm.v3' && (
                                    <SiHelm className="text-[#AAAAF9] text-xl"/>
                                )}
                                {component.type === 'yaml.k8s' && (
                                    <SiKubernetes className="text-[#1111F9] text-xl"/>
                                )}
                                {component.type === 'uwp' && (
                                    <SiWindows className="text-[#1111F9] text-xl"/>
                                )}
                                {component.properties['workload.type'] === 'binary' && (
                                    <LuBinary className="text-[#1111F9] text-xl"/>
                                )}
                            </TableCell>
                            <TableCell style={{ whiteSpace: 'nowrap' }}>{component.name}</TableCell>
                            <TableCell>
                                    {component.type === 'container' && (
                                        <span style={{ whiteSpace: 'nowrap' }}>{getImageName(getImage(component))}</span>
                                    )}
                                    {component.type === 'helm.v3' && (
                                        <span style={{ whiteSpace: 'nowrap' }}>{getProperty(component, 'chart')?.repo ?? '(unknown)'}</span>
                                    )}
                                    {component.type === 'yaml.k8s' && (
                                        <span style={{ whiteSpace: 'nowrap' }}>{`[object]`}</span>
                                    )}
                                    {component.type === 'uwp' && (
                                        <span style={{ whiteSpace: 'nowrap' }}>{getImage(component)}</span>
                                    )}
                                    {component.properties['workload.name'] != undefined && (
                                        <span style={{ whiteSpace: 'nowrap' }}>{component.properties['workload.name']}</span>
                                    )}
                            </TableCell>
                            <TableCell>
                                    {component.type === 'container' && (
                                        <span>
                                            {getImageVersion(getImage(component))}
                                        </span>
                                    )}
                                    {component.type === 'helm.v3' && (
                                        <span>{getProperty(component, 'chart')?.version ?? '(unknown)'}</span>
                                    )}
                                    {component.type === 'yaml.k8s' && (
                                        <span>{`n/a`}</span>
                                    )}
                                    {component.type === 'uwp' && (
                                        <span>{getProperty(component, 'app.version') ?? '(unknown)'}</span>
                                    )}
                                    {component.properties['workload.type'] != undefined && (
                                        <span style={{ whiteSpace: 'nowrap' }}>{component.properties['workload.type']}</span>
                                    )}
                            </TableCell>
                        </TableRow>
                    ))}
                </TableBody>
            </Table>
        </>
    );
}
export default SolutionVersionSpecCard;
