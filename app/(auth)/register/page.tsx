import RegisterForm from '@/components/RegisterForm'

export default async function Page(props: { searchParams: Promise<{ next?: string }> }) {
  const { next } = await props.searchParams
  return <RegisterForm next={next ?? ''} />
}
